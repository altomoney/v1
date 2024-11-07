// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca
import {FullMath} from "tap-token/options/FullMath.sol";
import {IPearlmit, PearlmitHandler} from "tap-utils/pearlmit/PearlmitHandler.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {TWLBase, Bucket} from "tap-token/governance/TWLBase.sol";
import {IYieldBox} from "../interfaces/IYieldBox.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

struct Participation {
    uint128 lockedAt; // lock start date
    uint128 expiry; // lock expiration date
    uint128 exerciseDiscountRate; // exercise discount rate
    uint8 bucketId;
    address tSglAddress;
    uint256 sglShares; // amount of YieldBox shares locked
    uint256 totalUsdoLent; // amount of usdo lent
    uint256 amountExercisedCurrentEpoch;
    uint256 lastEpochSync;
}

struct PaymentTokenOracle {
    ITapiocaOracle oracle;
    bytes oracleData;
}

struct SingularityPool {
    bool active;
    bool rescue; // If true, the pool will be used to rescue funds in case of emergency
    uint256 poolWeight;
}

contract TapiocaOptionBroker is Pausable, Ownable, PearlmitHandler, FullMath, ReentrancyGuard, TWLBase {
    using SafeERC20 for IERC20;

    TapToken public immutable TAP_TOKEN;
    IYieldBox public immutable YIELD_BOX;
    ITapiocaOracle public _tapOracle;
    ICluster public _cluster;

    bytes public _tapOracleData;

    uint256 public _epochTAPValuation; // TAP price for the current epoch

    address public _paymentTokenBeneficiary; // Where to collect the payment tokens

    address[] public _singularities; // Array of active singularity asset IDs

    mapping(address => mapping(uint256 => mapping(address => Participation))) public _participations; // accountAddress => bucketId => tSGL address => Participation
    mapping(uint256 => mapping(address => uint256)) public _singularityGauges; // epoch => tSGL address => availableTAP
    mapping(address => SingularityPool) public _singularityPools;
    mapping(address => PaymentTokenOracle) public _paymentTokens; // Token address => PaymentTokenOracle
    mapping(uint256 => mapping(address => int256)) public _netDepositedForEpoch; // epoch => tSglAddress => total deposited
    uint256 public _emergencySweepCooldown = 2 days;
    uint256 public _lastEmergencySweep;
    uint256 public _totalSingularityPoolWeights;

    error NotEqualDurations();
    error NotAuthorized();
    error NoActiveSingularities();
    error NoLiquidity();
    error OptionExpired();
    error PaymentTokenNotSupported();
    error OneEpochCooldown();
    error SingularityNotActive();
    error DurationTooShort();
    error PositionNotValid();
    error LockNotExpired();
    error TooSoon();
    error Failed();
    error TransferFailed();
    error SingularityInRescueMode();
    error PaymentTokenValuationNotValid();
    error LockExpired();
    error AdvanceEpochFirst();
    error DurationNotMultiple();
    error NotValid();
    error EpochTooLow();
    error SharesNotValid();
    error MinRewardTooLow();
    error EmergencySweepActivated();
    error TooHigh();
    error TooLong();
    error TooLow();

    constructor(
        address payable tapOFT,
        address paymentTokenBeneficiary,
        uint256 epochDuration,
        address pearlmit,
        address yieldbox,
        Bucket[] memory buckets,
        address admin
    ) PearlmitHandler(IPearlmit(pearlmit)) TWLBase(epochDuration, buckets) {
        TAP_TOKEN = TapToken(tapOFT);
        YIELD_BOX = IYieldBox(yieldbox);
        _paymentTokenBeneficiary = paymentTokenBeneficiary;

        _transferOwnership(admin);
    }

    // ==========
    //   EVENTS
    // ==========
    event Participate(
        address indexed user,
        uint256 indexed bucketId,
        address indexed tSglAddress,
        uint256 epoch,
        uint256 sglDeposit,
        uint256 lentUsdo
    );

    event ExerciseOption(
        address indexed user,
        uint256 indexed epoch,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tapAmount
    );
    event NewEpoch(uint256 indexed epoch, uint256 extractedTap, uint256 epochTapValuation);
    event ExitPosition(
        address indexed user, uint256 indexed bucketId, address indexed tSglAddress, uint256 epoch, uint256 sglShares
    );
    event SetPaymentToken(address indexed paymentToken, address oracle, bytes oracleData);
    event SetTapOracle(address oracle, bytes oracleData);
    event SetPaymentTokenBeneficiary(address paymentTokenBeneficiary);
    event SetCluster(address cluster);
    event Pause(bool pauseState);
    event SetTapOft(address tapOFT);
    event RequestSglPoolRescue(uint256 indexed tSglAddress, uint256 timestamp);
    event ActivateSGLPoolRescue(uint256 indexed tSglAddress, address sglAddress);
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();
    event PaymentCollection(address indexed paymentToken, address indexed beneficiary, uint256 amount);
    event SingularityConfigUpdate(address indexed tSglAddress, uint256 poolWeight, bool active, bool rescue);

    // ==========
    //    READ
    // ==========
    /// @notice Returns the current epoch given a timestamp
    function timestampToEpoch(uint256 timestamp) external view returns (uint256) {
        if (timestamp == 0) {
            timestamp = block.timestamp;
        }
        if (timestamp < INIT_TIMESTAMP) return 0;

        return _timestampToEpoch(timestamp);
    }

    /// @dev Keep compatibility with previous interface
    function getCurrentWeek() external view returns (uint256) {
        return currentEpoch();
    }

    /// @notice Returns the details of an oTAP position
    /// @param user User address
    /// @param bucketId Bucket ID to check the participation
    /// @return participation
    function getParticipation(address user, uint8 bucketId, address tSGLAddress)
        external
        view
        returns (Participation memory)
    {
        return _participations[user][bucketId][tSGLAddress];
    }

    /// @notice Returns the details of TOLP Singularity Pool, twAML pool and gauge for a given tSglAddress
    function getSingularityPoolInfo(address tSGLAddress) external view returns (SingularityPool memory) {
        return _singularityPools[tSGLAddress];
    }

    /// @notice Returns the details of an OTC deal
    function getOTCDealDetails(
        address from,
        uint256 bucketId,
        address tSglAddress,
        address paymentToken,
        uint256 buyAmount
    ) external view returns (uint256 eligibleTapAmount, uint256 paymentTokenAmount, uint256 tapAmount) {
        // Load data
        Participation memory position = _participations[from][bucketId][tSglAddress];

        if (!_isPositionActive(position)) revert OptionExpired();

        uint256 cachedEpoch = currentEpoch();

        PaymentTokenOracle memory paymentTokenOracle = _paymentTokens[paymentToken];

        if (paymentTokenOracle.oracle == ITapiocaOracle(address(0))) {
            revert PaymentTokenNotSupported();
        }

        if (block.timestamp < position.lockedAt + EPOCH_DURATION) {
            revert OneEpochCooldown();
        }

        {
            uint256 gaugeTotalForEpoch = _singularityGauges[cachedEpoch][tSglAddress];
            uint256 netAmount = uint256(_netDepositedForEpoch[cachedEpoch][tSglAddress]);
            if (netAmount == 0) revert NoLiquidity();

            eligibleTapAmount = muldiv(position.totalUsdoLent, gaugeTotalForEpoch, netAmount);
            eligibleTapAmount -= position.amountExercisedCurrentEpoch;
            if (eligibleTapAmount < buyAmount) revert TooHigh();
        }

        tapAmount = buyAmount == 0 ? eligibleTapAmount : buyAmount;
        if (tapAmount < 1e18) revert TooLow();
        // Get TAP valuation
        uint256 otcAmountInUSD = tapAmount * _epochTAPValuation;
        // Get payment token valuation
        (, uint256 paymentTokenValuation) = paymentTokenOracle.oracle.peek(paymentTokenOracle.oracleData);
        // Get payment token amount
        paymentTokenAmount = _getDiscountedPaymentAmount(
            otcAmountInUSD,
            paymentTokenValuation,
            position.exerciseDiscountRate,
            IERC20Metadata(paymentToken).decimals()
        );
    }

    // ===========
    //    WRITE
    // ===========

    /// @notice Participate in voting and mint an oTAP position.
    ///         Exercising the option is not possible on participation week.
    function participatePeer(address to, uint8 bucketId, address tSGLAddress, uint256 sglShares, uint256 usdoAmount)
        external
        whenNotPaused
        nonReentrant
    {
        if (lastEpoch != currentEpoch()) advanceWeek();
        if (!_cluster.hasRole(msg.sender, keccak256("MAGNETAR"))) {
            revert NotAuthorized();
        }
        if (sglShares == 0 || usdoAmount == 0) revert SharesNotValid();
        if (!_singularityPools[tSGLAddress].active) revert SingularityNotActive();
        if (_singularityPools[tSGLAddress].rescue) revert SingularityInRescueMode();
        if (_lastEmergencySweep != 0) revert EmergencySweepActivated();

        _supplyInBucket(bucketId, usdoAmount);

        // Create the participation position
        Participation storage position = _participations[to][bucketId][tSGLAddress];
        Bucket memory bucket = buckets[bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);

        if (position.expiry > 0 && block.timestamp < position.expiry) {
            // Clear the expected votes at the past expected expiration date
            _netDepositedForEpoch[_timestampToEpoch(position.expiry) + 1][tSGLAddress] -= int256(position.totalUsdoLent);
        }

        position.bucketId = bucketId;
        position.tSglAddress = tSGLAddress;
        position.sglShares = sglShares;
        position.totalUsdoLent += usdoAmount;
        position.exerciseDiscountRate = bucket.rewardsMultiplier;
        position.lockedAt = uint56(block.timestamp);
        position.expiry = uint56(expiry);

        _netDepositedForEpoch[currentEpoch() + 1][tSGLAddress] += int256(usdoAmount);
        _netDepositedForEpoch[_timestampToEpoch(expiry) + 1][tSGLAddress] -= int256(position.totalUsdoLent);

        IERC20(tSGLAddress).safeTransferFrom(msg.sender, address(this), sglShares);

        emit Participate(to, bucketId, tSGLAddress, currentEpoch(), sglShares, usdoAmount);
    }

    /// @notice Exit a twAML participation and delete the voting power if existing
    function exitPositionPeer(address from, uint8 bucketId, address tSGLAddress) external whenNotPaused {
        if (!_cluster.hasRole(msg.sender, keccak256("MAGNETAR"))) {
            revert NotAuthorized();
        }
        Participation storage position = _participations[from][bucketId][tSGLAddress];
        SingularityPool storage pool = _singularityPools[tSGLAddress];

        if (block.timestamp < position.expiry) {
            revert LockNotExpired();
        }

        uint256 sglShares = position.sglShares;

        position.sglShares = 0;

        IERC20(tSGLAddress).safeTransfer(msg.sender, sglShares);

        emit ExitPosition(from, bucketId, tSGLAddress, currentEpoch(), sglShares);
    }

    /// @notice Exercise an oTAP position
    /// @param bucketId tokenId of the oTAP position, position must be active
    /// @param paymentToken Address of the payment token to use, must be whitelisted
    /// @param tapAmount Amount of TAP to exercise. If 0, the full amount is exercised
    function exerciseOption(uint256 bucketId, address tSGLAddress, address paymentToken, uint256 tapAmount)
        external
        whenNotPaused
    {
        Participation storage position = _participations[msg.sender][bucketId][tSGLAddress];

        if (!_isPositionActive(position)) revert OptionExpired();

        uint256 cachedEpoch = currentEpoch();

        // Check requirements
        if (address(_paymentTokens[paymentToken].oracle) == address(0)) {
            revert PaymentTokenNotSupported();
        }

        if (_timestampToEpoch(block.timestamp) > cachedEpoch) revert AdvanceEpochFirst();

        if (block.timestamp < position.lockedAt + EPOCH_DURATION) {
            revert OneEpochCooldown();
        }

        // Get eligible OTC amount
        uint256 gaugeTotalForEpoch = _singularityGauges[cachedEpoch][tSGLAddress];
        uint256 netAmount = uint256(_netDepositedForEpoch[cachedEpoch][tSGLAddress]);
        uint256 eligibleTapAmount = muldiv(position.totalUsdoLent, gaugeTotalForEpoch, netAmount);

        eligibleTapAmount -= position.amountExercisedCurrentEpoch;

        if (eligibleTapAmount < tapAmount) revert TooHigh();

        uint256 chosenAmount = tapAmount == 0 ? eligibleTapAmount : tapAmount;
        if (chosenAmount < 1e18) revert TooLow();
        position.amountExercisedCurrentEpoch += chosenAmount;

        // Finalize the deal
        uint256 paymentAmount = _processOTCDeal(paymentToken, chosenAmount, position.exerciseDiscountRate);

        emit ExerciseOption(msg.sender, cachedEpoch, paymentToken, paymentAmount, chosenAmount);
    }

    /// @notice Start a new epoch, extract TAP from the TapOFT contract,
    ///         emit it to the active singularities and get the price of TAP for the epoch.
    function advanceWeek() public {
        if (lastEpoch == currentEpoch()) revert NotValid();

        _syncTWLBuckets(currentEpoch() - lastEpoch);

        // Get epoch TAP valuation
        bool success;
        (success, _epochTAPValuation) = _tapOracle.get(_tapOracleData);
        if (!success) revert Failed();

        // Extract TAP + emit to gauges
        uint256 epochTAP = TAP_TOKEN.emitForWeek();
        _emitToGauges(epochTAP);

        lastEpoch = currentEpoch();
        emit NewEpoch(lastEpoch, epochTAP, _epochTAPValuation);
    }

    // =========
    //   OWNER
    // =========

    /// @notice Set the TapOFT Oracle address and data
    /// @param tapOracle The new TapOFT Oracle address
    /// @param tapOracleData The new TapOFT Oracle data
    function setTapOracle(address tapOracle, bytes calldata tapOracleData) external onlyOwner {
        _tapOracle = ITapiocaOracle(tapOracle);
        _tapOracleData = tapOracleData;

        emit SetTapOracle(tapOracle, tapOracleData);
    }

    /// @notice Activate or deactivate a payment token
    /// @dev set the oracle to address(0) to deactivate, expect the same decimal precision as TAP oracle
    function setPaymentToken(address paymentToken, address oracle, bytes calldata oracleData) external onlyOwner {
        _paymentTokens[paymentToken].oracle = ITapiocaOracle(oracle);
        _paymentTokens[paymentToken].oracleData = oracleData;

        emit SetPaymentToken(paymentToken, oracle, oracleData);
    }

    /// @notice Set the payment token beneficiary
    /// @param paymentTokenBeneficiary The new payment token beneficiary
    function setPaymentTokenBeneficiary(address paymentTokenBeneficiary) external onlyOwner {
        _paymentTokenBeneficiary = paymentTokenBeneficiary;
        emit SetPaymentTokenBeneficiary(paymentTokenBeneficiary);
    }

    /// @notice Collect the payment tokens from the OTC deals
    /// @param paymentTokens The payment tokens to collect
    function collectPaymentTokens(address[] calldata paymentTokens) external onlyOwner nonReentrant {
        address paymentTokenBeneficiary = _paymentTokenBeneficiary;
        if (paymentTokenBeneficiary == address(0)) {
            revert PaymentTokenNotSupported();
        }

        for (uint256 i; i < paymentTokens.length; ++i) {
            IERC20 paymentToken = IERC20(paymentTokens[i]);
            uint256 balance = paymentToken.balanceOf(address(this));

            paymentToken.safeTransfer(paymentTokenBeneficiary, balance);

            emit PaymentCollection(address(paymentToken), paymentTokenBeneficiary, balance);
        }
    }

    /**
     * @notice updates the Cluster address.
     * @dev can only be called by the owner.
     * @param cluster the new address.
     */
    function setCluster(address cluster) external onlyOwner {
        if (cluster == address(0)) revert NotValid();

        _cluster = ICluster(cluster);

        emit SetCluster(cluster);
    }

    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool pauseState) external {
        if (!_cluster.hasRole(msg.sender, keccak256("PAUSABLE")) && msg.sender != owner()) revert NotAuthorized();
        if (pauseState) {
            _pause();
        } else {
            _unpause();
        }
        emit Pause(pauseState);
    }

    /**
     * @notice Add a new bucket
     * @param bucket Bucket to add into the system
     */
    function addBucket(Bucket memory bucket) external override onlyOwner {
        _addBucket(bucket);
    }

    /**
     * @notice Updates an existing bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system
     * @dev Ignores the lockEpochDuration field.
     */
    function updateBucket(uint8 index, Bucket memory bucket) external override onlyOwner {
        _updateBucket(index, bucket);
    }

    /**
     * @notice Set the emergency sweep cooldown
     */
    function setEmergencySweepCooldown(uint256 emergencySweepCooldown) external onlyOwner {
        _emergencySweepCooldown = emergencySweepCooldown;
        emit SetEmergencySweepCooldown(emergencySweepCooldown);
    }

    /**
     * @notice Activate the emergency sweep cooldown
     */
    function activateEmergencySweep() external onlyOwner {
        _lastEmergencySweep = block.timestamp;
        emit ActivateEmergencySweep();
    }

    /// @notice Set the config of a singularity pool (weight, active, rescue mode)
    /// @param tSglAddress The address of the singularity pool
    /// @param config The new singularity config
    function setSingularityConfig(address tSglAddress, SingularityPool memory config) external onlyOwner {
        _singularityPools[tSglAddress] = config;

        // Update total weights
        _totalSingularityPoolWeights = 0;
        for (uint256 i; i < _singularities.length; i++) {
            SingularityPool memory sgl = _singularityPools[(_singularities[i])];
            if (!sgl.rescue && sgl.active) {
                _totalSingularityPoolWeights += sgl.poolWeight;
            }
        }

        emit SingularityConfigUpdate(tSglAddress, config.poolWeight, config.active, config.rescue);
    }
    // ============
    //   INTERNAL
    // ============

    function _timestampToEpoch(uint256 timestamp) internal view returns (uint256) {
        return ((timestamp - INIT_TIMESTAMP) / EPOCH_DURATION);
    }

    /// @notice Check if a position is active, whether it is expired or SGL is in rescue mode
    /// @dev Check if the current week is less than or equal the expiry week
    /// @return isPositionActive True if the position is active
    function _isPositionActive(Participation memory participation) internal view returns (bool) {
        if (participation.expiry == 0) revert PositionNotValid();
        if (_singularityPools[participation.tSglAddress].rescue) revert SingularityInRescueMode();

        uint256 expirationEpoch = _timestampToEpoch(participation.expiry);

        return currentEpoch() <= expirationEpoch;
    }

    /// @notice Process the OTC deal, transfer the payment token to the broker and the TAP amount to the user
    /// @param paymentToken The payment token
    /// @param tapAmount The amount of TAP that the user has to receive
    /// @param discount The discount that the user has to apply to the OTC deal
    function _processOTCDeal(address paymentToken, uint256 tapAmount, uint256 discount)
        internal
        returns (uint256 discountedPaymentAmount)
    {
        // Get TAP valuation
        uint256 otcAmountInUSD = tapAmount * _epochTAPValuation;

        // Get payment token valuation
        (bool success, uint256 paymentTokenValuation) =
            _paymentTokens[paymentToken].oracle.get(_paymentTokens[paymentToken].oracleData);
        if (!success) revert Failed();

        // Calculate payment amount and initiate the transfers
        discountedPaymentAmount =
            _getDiscountedPaymentAmount(otcAmountInUSD, paymentTokenValuation, discount, ERC20(paymentToken).decimals());

        IERC20(paymentToken).transferFrom(msg.sender, address(this), discountedPaymentAmount);

        TAP_TOKEN.extractTAP(msg.sender, tapAmount);

        return discountedPaymentAmount;
    }

    /// @notice Computes the discounted payment amount for a given OTC amount in USD
    /// @param _otcAmountInUSD The OTC amount in USD, 18 decimals
    /// @param _paymentTokenValuation The payment token valuation in USD, 18 decimals
    /// @param _discount The discount in BPS
    /// @param _paymentTokenDecimals The payment token decimals
    /// @return paymentAmount The discounted payment amount
    function _getDiscountedPaymentAmount(
        uint256 _otcAmountInUSD,
        uint256 _paymentTokenValuation,
        uint256 _discount,
        uint256 _paymentTokenDecimals
    ) internal pure returns (uint256 paymentAmount) {
        if (_paymentTokenValuation == 0) revert PaymentTokenValuationNotValid();

        uint256 discountedOTCAmountInUSD = _otcAmountInUSD - muldiv(_otcAmountInUSD, _discount, 100e4); // 1e4 is discount decimals, 100 is discount percentage

        // Calculate payment amount
        paymentAmount = discountedOTCAmountInUSD / _paymentTokenValuation;

        if (_paymentTokenDecimals <= 18) {
            paymentAmount = paymentAmount / (10 ** (18 - _paymentTokenDecimals));
        } else {
            paymentAmount = paymentAmount * (10 ** (_paymentTokenDecimals - 18));
        }
    }

    /// @notice Emit TAP to the gauges equitably and update the net deposited amounts for each pool
    /// @dev Assume the epoch has been updated
    function _emitToGauges(uint256 epochTAP) internal {
        uint256 totalWeights = _totalSingularityPoolWeights;
        uint256 epoch = currentEpoch();
        // For each pool
        for (uint256 i; i < _singularities.length; ++i) {
            address tSglAddress = _singularities[i];
            uint256 currentPoolWeight = _singularityPools[tSglAddress].poolWeight;
            uint256 quotaPerSingularity = muldiv(currentPoolWeight, epochTAP, totalWeights);
            // Emit weekly TAP to the pool
            _singularityGauges[epoch][tSglAddress] = quotaPerSingularity;

            // Update net deposited amounts
            mapping(address tSglAddress => int256 netAmount) storage prev = _netDepositedForEpoch[epoch - 1];
            mapping(address tSglAddress => int256 netAmount) storage curr = _netDepositedForEpoch[epoch];

            // Pass previous epoch net amount to the next epoch
            // Expired positions are offset, check `participate()`
            curr[tSglAddress] += prev[tSglAddress];
        }
    }
}
