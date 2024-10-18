// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    address sglAddress;
    uint256 sglAssetID; // Singularity market YieldBox asset ID
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
    uint256 totalUsdoLocked; // total amount of YieldBox shares deposited, used for pool share calculation
}

contract TapiocaOptionBroker is Pausable, Ownable, PearlmitHandler, FullMath, ReentrancyGuard, TWLBase {
    using SafeERC20 for IERC20;

    TapToken public immutable TAP_TOKEN;
    IYieldBox public immutable YIELD_BOX;
    ITapiocaOracle public tapOracle;
    ICluster public cluster;

    bytes public tapOracleData;

    uint256 public epochTAPValuation; // TAP price for the current epoch

    address public paymentTokenBeneficiary; // Where to collect the payment tokens

    uint256[] public singularities; // Array of active singularity asset IDs

    mapping(address => mapping(uint256 => mapping(uint256 => Participation))) public participations; // accountAddress => bucketId => sglId => Participation
    mapping(uint256 => mapping(uint256 => uint256)) public singularityGauges; // epoch => sglAssetId => availableTAP
    mapping(uint256 => SingularityPool) public singularityPools;
    mapping(address => PaymentTokenOracle) public paymentTokens; // Token address => PaymentTokenOracle
    mapping(uint256 => mapping(uint256 => int256)) public netDepositedForEpoch; // epoch => sgl => total deposited
    uint256 public emergencySweepCooldown = 2 days;
    uint256 public lastEmergencySweep;

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

    constructor(
        address payable _tapOFT,
        address _paymentTokenBeneficiary,
        uint256 _epochDuration,
        address _pearlmit,
        address _yieldbox,
        Bucket[] memory _buckets,
        address _owner
    ) PearlmitHandler(IPearlmit(_pearlmit)) TWLBase(_epochDuration, _buckets) {
        TAP_TOKEN = TapToken(_tapOFT);
        YIELD_BOX = IYieldBox(_yieldbox);
        paymentTokenBeneficiary = _paymentTokenBeneficiary;

        _transferOwnership(_owner);
    }

    // ==========
    //   EVENTS
    // ==========
    event Participate(
        address indexed user,
        uint256 indexed sglAssetId,
        uint256 indexed bucketId,
        uint256 epoch,
        uint256 sglDeposit,
        uint256 lentUsdo
    );

    event ExerciseOption(uint256 indexed epoch, address indexed to, address indexed paymentToken, uint256 tapAmount);
    event NewEpoch(uint256 indexed epoch, uint256 extractedTap, uint256 epochTapValuation);
    event ExitPosition(
        address indexed user, uint256 indexed sglAssetId, uint256 indexed bucketId, uint256 epoch, uint256
    );
    event SetPaymentToken(ERC20 indexed paymentToken, ITapiocaOracle oracle, bytes oracleData);
    event SetTapOracle(ITapiocaOracle oracle, bytes oracleData);
    event SetPaymentTokenBeneficiary(address paymentTokenBeneficiary);
    event CollectPaymentTokens(address[] paymentTokens);
    event SetCluster(ICluster cluster);
    event Pause(bool pauseState);
    event SetTapOft(address tapOFT);
    event RequestSglPoolRescue(uint256 indexed sglAssetId, uint256 timestamp);
    event ActivateSGLPoolRescue(uint256 indexed sglAssetId, address sglAddress);
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();

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
    function getParticipation(address user, uint8 bucketId, uint256 sglId)
        external
        view
        returns (Participation memory)
    {
        return participations[user][bucketId][sglId];
    }

    /// @notice Returns the details of TOLP Singularity Pool, twAML pool and gauge for a given sglAssetId
    /// @param _singularity The singularity address
    /// @param epochId The epoch id of which to get the tap emitted for the pool - if 0, current epoch will be used
    /// @return assetId The Singularity asset id = YB asset id
    /// @return totalDeposited The total deposited amount in the pool
    /// @return weight The weight of the pool
    /// @return isInRescue True if the singularity is in rescue mode
    /// @return tapEmittedInCurrentEpoch The amount of TAP emitted in the current epoch
    /// @return lastEpochCumulative The last epoch cumulative for the pool
    /// @return lastTotalDeposited The last total deposited for the pool
    function getSingularityPoolInfo(uint256 sglId)
        external
        view
        returns (
            SingularityPool memory
        )
    {
        return singularityPools[sglId];
    }

    /// @notice Returns the details of an OTC deal for a given oTAP token ID and a payment token.
    ///         The oracle uses the last peeked value, and not the latest one, so the payment amount may be different.
    /// @param _bucketId The oTAP token ID
    /// @param _paymentToken The payment token
    /// @param _tapAmount The amount of TAP to be exchanged. If 0 it will use the full amount of TAP eligible for the deal
    /// @return eligibleTapAmount The amount of TAP eligible for the deal
    /// @return paymentTokenAmount The amount of payment tokens required for the deal
    /// @return tapAmount The amount of TAP to be exchanged
    function getOTCDealDetails(uint256 _bucketId, ERC20 _paymentToken, uint256 _tapAmount)
        external
        view
        returns (uint256 eligibleTapAmount, uint256 paymentTokenAmount, uint256 tapAmount)
    {
        // Load data
        //(, TapOption memory oTAPPosition) = oTAP.attributes(_bucketId);
        //LockPosition memory tOLPLockPosition = tOLP.getLock(oTAPPosition.tOLP);

        /*
        {
            if (!_isPositionActive(tOLPLockPosition)) revert OptionExpired();
        }

        uint256 cachedEpoch = epoch;

        PaymentTokenOracle memory paymentTokenOracle = paymentTokens[_paymentToken];

        // Check requirements
        if (paymentTokenOracle.oracle == ITapiocaOracle(address(0))) {
            revert PaymentTokenNotSupported();
        }
        if (block.timestamp < tOLPLockPosition.lockTime + EPOCH_DURATION) {
            revert OneEpochCooldown();
        } // Can only exercise after 1 epoch duration

        // Get eligible OTC amount
        {
            uint256 gaugeTotalForEpoch = singularityGauges[cachedEpoch][tOLPLockPosition.sglAssetID];
            uint256 netAmount = uint256(netDepositedForEpoch[cachedEpoch][tOLPLockPosition.sglAssetID]);
            if (netAmount == 0) revert NoLiquidity();

            eligibleTapAmount = muldiv(tOLPLockPosition.ybShares, gaugeTotalForEpoch, netAmount);
            eligibleTapAmount -= oTAPCalls[_bucketId][cachedEpoch]; // Subtract already exercised amount
            if (eligibleTapAmount < _tapAmount) revert TooHigh();
        }

        tapAmount = _tapAmount == 0 ? eligibleTapAmount : _tapAmount;
        if (tapAmount < 1e18) revert TooLow();
        // Get TAP valuation
        uint256 otcAmountInUSD = tapAmount * epochTAPValuation; // Divided by TAP decimals
        // Get payment token valuation
        (, uint256 paymentTokenValuation) = paymentTokenOracle.oracle.peek(paymentTokenOracle.oracleData);
        // Get payment token amount
        paymentTokenAmount = _getDiscountedPaymentAmount(
            otcAmountInUSD, paymentTokenValuation, oTAPPosition.discount, _paymentToken.decimals()
        );
        */
    }

    // ===========
    //    WRITE
    // ===========

    /// @notice Participate in voting and mint an oTAP position.
    ///         Exercising the option is not possible on participation week.
    function participatePeer(address to, uint8 bucketId, uint256 sglId, uint256 sglShares, uint256 usdoAmount)
        external
        whenNotPaused
        nonReentrant
    {
        // Caller must check if user debt covers the lock
        SingularityPool memory sgl = singularityPools[sglId];
        if (lastEpoch != currentEpoch()) advanceWeek();
        if (!cluster.hasRole(msg.sender, keccak256("MAGNETAR"))) {
            revert NotAuthorized();
        }
        if (sglShares == 0 || usdoAmount == 0) revert SharesNotValid();
        if (sglId == 0 || !sgl.active) revert SingularityNotActive();
        if (sgl.rescue) revert SingularityInRescueMode();
        if (lastEmergencySweep != 0) revert EmergencySweepActivated();

        bool isErr = pearlmit.transferFromERC1155(msg.sender, address(this), address(YIELD_BOX), sglId, sglShares);
        if (isErr) {
            revert TransferFailed();
        }

        _supplyInBucket(bucketId, usdoAmount);

        // Create the participation position
        Participation storage position = participations[to][bucketId][sglId];
        Bucket memory bucket = buckets[bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);

        if (position.expiry > 0 && block.timestamp < position.expiry) {
            // Clear the expected votes at the past expected expiration date
            netDepositedForEpoch[_timestampToEpoch(position.expiry) + 1][sglId] -= int256(position.totalUsdoLent);
        }

        position.bucketId = bucketId;
        position.sglAssetID = sglId;
        position.sglShares = sglShares;
        position.totalUsdoLent += usdoAmount;
        position.exerciseDiscountRate = bucket.rewardsMultiplier;
        position.lockedAt = uint56(block.timestamp);
        position.expiry = uint56(expiry);

        // Record amount for next epoch exercise
        netDepositedForEpoch[currentEpoch() + 1][sglId] += int256(usdoAmount);

        uint256 lastEpoch = _timestampToEpoch(expiry);
        // And remove it from last epoch
        // Math is safe, check `_emitToGauges()`
        netDepositedForEpoch[lastEpoch + 1][sglId] -= int256(position.totalUsdoLent);

        IERC20((msg.sender, address(this), address(YIELD_BOX), sglId, sglShares);
        if (isErr) {
            revert TransferFailed();
        }
        emit Participate(to, currentEpoch(), bucketId, sglId, sglShares, usdoAmount);
    }

    /// @notice Exit a twAML participation and delete the voting power if existing
    function exitPositionPeer(address from, uint8 bucketId, uint256 sglId) external whenNotPaused {
        if (!cluster.hasRole(msg.sender, keccak256("MAGNETAR"))) {
            revert NotAuthorized();
        }
        Participation storage position = participations[from][bucketId][sglId];
        SingularityPool storage pool = singularityPools[sglId];

        // If SGL is in rescue, bypass the lock expiration
        if (block.timestamp < lock.expiry && !pool.rescue) {
            revert LockNotExpired();
        }

        pool.totalUsdoLocked -= position.totalUsdoLent;

        emit ExitPosition(from, bucketId, sglId, currentEpoch());
    }

    /// @notice Exercise an oTAP position
    /// @param _bucketId tokenId of the oTAP position, position must be active
    /// @param _paymentToken Address of the payment token to use, must be whitelisted
    /// @param _tapAmount Amount of TAP to exercise. If 0, the full amount is exercised
    function exerciseOption(uint256 _bucketId, ERC20 _paymentToken, uint256 _tapAmount) external whenNotPaused {
        // Load data
        /*
        (address owner, TapOption memory oTAPPosition) = oTAP.attributes(_bucketId);
        LockPosition memory tOLPLockPosition = tOLP.getLock(oTAPPosition.tOLP);
        {
            bool isPositionActive = _isPositionActive(tOLPLockPosition);
            if (!isPositionActive) revert OptionExpired();
        }

        uint256 cachedEpoch = epoch;

        PaymentTokenOracle memory paymentTokenOracle = paymentTokens[_paymentToken];

        // Check requirements
        if (paymentTokenOracle.oracle == ITapiocaOracle(address(0))) {
            revert PaymentTokenNotSupported();
        }

        // Check allowance. Make sure to consume it post call
        {
            // oTAP.isApprovedOrOwner(msg.sender, _bucketId)
            if (owner != msg.sender && !isERC721Approved(owner, msg.sender, address(oTAP), _bucketId)) {
                revert NotAuthorized();
            }
        }

        if (_timestampToWeek(block.timestamp) > epoch) revert AdvanceEpochFirst();

        if (block.timestamp < oTAPPosition.entry + EPOCH_DURATION) {
            revert OneEpochCooldown();
        } // Can only exercise after 1 epoch duration

        // Get eligible OTC amount
        uint256 gaugeTotalForEpoch = singularityGauges[cachedEpoch][tOLPLockPosition.sglAssetID];
        uint256 netAmount = uint256(netDepositedForEpoch[cachedEpoch][tOLPLockPosition.sglAssetID]);
        uint256 eligibleTapAmount = muldiv(tOLPLockPosition.ybShares, gaugeTotalForEpoch, netAmount);
        eligibleTapAmount -= oTAPCalls[_bucketId][cachedEpoch]; // Subtract already exercised amount
        if (eligibleTapAmount < _tapAmount) revert TooHigh();

        uint256 chosenAmount = _tapAmount == 0 ? eligibleTapAmount : _tapAmount;
        if (chosenAmount < 1e18) revert TooLow();
        oTAPCalls[_bucketId][cachedEpoch] += chosenAmount; // Adds up exercised amount to current epoch

        // Finalize the deal
        _processOTCDeal(_paymentToken, paymentTokenOracle, chosenAmount, oTAPPosition.discount);

        emit ExerciseOption(cachedEpoch, msg.sender, _paymentToken, _bucketId, chosenAmount);
        */
    }

    /**
     * @notice Refresh the total deposited amount for the given SGL assets
     */
    function refreshTotalDeposited(uint256[] calldata sglAssetId) external returns (uint256[] memory totalDeposited) {
        uint256 len = sglAssetId.length;
        totalDeposited = new uint256[](len);
        for (uint256 i; i < len; i++) {
            totalDeposited[i] = _snapshotTotalDepositedForSgl(sglAssetId[i]);
        }
    }

    /// @notice Start a new epoch, extract TAP from the TapOFT contract,
    ///         emit it to the active singularities and get the price of TAP for the epoch.
    function advanceWeek() public {
        if (lastEpoch == currentEpoch()) revert NotValid();

        //uint256 sglLen = singularities.length;
        //if (sglLen == 0) revert NoActiveSingularities();

        _syncTWLBuckets(currentEpoch() - lastEpoch);

        // Extract TAP + emit to gauges
        uint256 epochTAP = TAP_TOKEN.emitForWeek();
        _emitToGauges(epochTAP);

        // Get epoch TAP valuation
        bool success;
        (success, epochTAPValuation) = tapOracle.get(tapOracleData);
        if (!success) revert Failed();

        lastEpoch = currentEpoch();
        emit NewEpoch(lastEpoch, epochTAP, epochTAPValuation);
    }

    /// @notice Claim the Broker role of the oTAP contract. Init emissions on TOB and TapToken.
    /// @dev Can only be called once. External calls should revert if already called.
    function init() external {
        //oTAP.brokerClaim();

        //emissionsStartTime = block.timestamp;
        //tapOFT.initEmissions();
    }

    // =========
    //   OWNER
    // =========

    /// @notice Set the TapOFT Oracle address and data
    /// @param _tapOracle The new TapOFT Oracle address
    /// @param _tapOracleData The new TapOFT Oracle data
    function setTapOracle(ITapiocaOracle _tapOracle, bytes calldata _tapOracleData) external onlyOwner {
        /*
        tapOracle = _tapOracle;
        tapOracleData = _tapOracleData;

        emit SetTapOracle(_tapOracle, _tapOracleData);
        */
    }

    /// @notice Activate or deactivate a payment token
    /// @dev set the oracle to address(0) to deactivate, expect the same decimal precision as TAP oracle
    function setPaymentToken(ERC20 _paymentToken, ITapiocaOracle _oracle, bytes calldata _oracleData)
        external
        onlyOwner
    {
        /*
        paymentTokens[_paymentToken].oracle = _oracle;
        paymentTokens[_paymentToken].oracleData = _oracleData;

        emit SetPaymentToken(_paymentToken, _oracle, _oracleData);
        */
    }

    /// @notice Set the payment token beneficiary
    /// @param _paymentTokenBeneficiary The new payment token beneficiary
    function setPaymentTokenBeneficiary(address _paymentTokenBeneficiary) external onlyOwner {
        paymentTokenBeneficiary = _paymentTokenBeneficiary;
        emit SetPaymentTokenBeneficiary(_paymentTokenBeneficiary);
    }

    function setSingularity(uint256 assetID, bool value) external onlyOwner {
        singularityPools[assetID].active = value;
    }

    /// @notice Collect the payment tokens from the OTC deals
    /// @param _paymentTokens The payment tokens to collect
    function collectPaymentTokens(address[] calldata _paymentTokens) external onlyOwner nonReentrant {
        address _paymentTokenBeneficiary = paymentTokenBeneficiary;
        if (_paymentTokenBeneficiary == address(0)) {
            revert PaymentTokenNotSupported();
        }

        for (uint256 i; i < _paymentTokens.length; ++i) {
            IERC20 paymentToken = IERC20(_paymentTokens[i]);
            paymentToken.safeTransfer(_paymentTokenBeneficiary, paymentToken.balanceOf(address(this)));
        }
        emit CollectPaymentTokens(_paymentTokens);
    }

    /**
     * @notice updates the Cluster address.
     * @dev can only be called by the owner.
     * @param _cluster the new address.
     */
    function setCluster(ICluster _cluster) external onlyOwner {
        if (address(_cluster) == address(0)) revert NotValid();
        cluster = _cluster;
        emit SetCluster(_cluster);
    }

    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool _pauseState) external {
        if (!cluster.hasRole(msg.sender, keccak256("PAUSABLE")) && msg.sender != owner()) revert NotAuthorized();
        if (_pauseState) {
            _pause();
        } else {
            _unpause();
        }
        emit Pause(_pauseState);
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
    function setEmergencySweepCooldown(uint256 _emergencySweepCooldown) external onlyOwner {
        emergencySweepCooldown = _emergencySweepCooldown;
        emit SetEmergencySweepCooldown(_emergencySweepCooldown);
    }

    /**
     * @notice Activate the emergency sweep cooldown
     */
    function activateEmergencySweep() external onlyOwner {
        lastEmergencySweep = block.timestamp;
        emit ActivateEmergencySweep();
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
        if (singularityPools[participation.sglAssetID].rescue) revert SingularityInRescueMode();

        uint256 expirationEpoch = _timestampToEpoch(participation.expiry);

        return currentEpoch() <= expirationEpoch;
    }

    /// @notice Process the OTC deal, transfer the payment token to the broker and the TAP amount to the user
    /// @param _paymentToken The payment token
    /// @param _paymentTokenOracle The oracle of the payment token
    /// @param tapAmount The amount of TAP that the user has to receive
    /// @param discount The discount that the user has to apply to the OTC deal
    function _processOTCDeal(
        ERC20 _paymentToken,
        PaymentTokenOracle memory _paymentTokenOracle,
        uint256 tapAmount,
        uint256 discount
    ) internal {
        // Get TAP valuation
        uint256 otcAmountInUSD = tapAmount * epochTAPValuation;

        // Get payment token valuation
        (bool success, uint256 paymentTokenValuation) = _paymentTokenOracle.oracle.get(_paymentTokenOracle.oracleData);
        if (!success) revert Failed();

        // Calculate payment amount and initiate the transfers
        uint256 discountedPaymentAmount =
            _getDiscountedPaymentAmount(otcAmountInUSD, paymentTokenValuation, discount, _paymentToken.decimals());

        bool isErr =
            pearlmit.transferFromERC20(msg.sender, address(this), address(_paymentToken), discountedPaymentAmount);
        if (isErr) revert TransferFailed();

        TAP_TOKEN.extractTAP(msg.sender, tapAmount);
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
        /*
        if (_paymentTokenValuation == 0) revert PaymentTokenValuationNotValid();

        uint256 discountedOTCAmountInUSD = _otcAmountInUSD - muldiv(_otcAmountInUSD, _discount, 100e4); // 1e4 is discount decimals, 100 is discount percentage

        // Calculate payment amount
        paymentAmount = discountedOTCAmountInUSD / _paymentTokenValuation;

        if (_paymentTokenDecimals <= 18) {
            paymentAmount = paymentAmount / (10 ** (18 - _paymentTokenDecimals));
        } else {
            paymentAmount = paymentAmount * (10 ** (_paymentTokenDecimals - 18));
        }
        */
    }

    /// @notice Emit TAP to the gauges equitably and update the net deposited amounts for each pool
    /// @dev Assume the epoch has been updated
    function _emitToGauges(uint256 _epochTAP) internal {
        /*
        SingularityPool[] memory sglPools = tOLP.getSingularityPools();
        uint256 totalWeights = tOLP.totalSingularityPoolWeights();

        uint256 len = sglPools.length;
        unchecked {
            // For each pool
            for (uint256 i; i < len; ++i) {
                uint256 currentPoolWeight = sglPools[i].poolWeight;
                uint256 quotaPerSingularity = muldiv(currentPoolWeight, _epochTAP, totalWeights);
                uint256 sglAssetID = sglPools[i].sglAssetID;
                // Emit weekly TAP to the pool
                singularityGauges[epoch][sglAssetID] = quotaPerSingularity;

                // Update net deposited amounts
                mapping(uint256 sglAssetID => int256 netAmount) storage prev = netDepositedForEpoch[epoch - 1];
                mapping(uint256 sglAssetID => int256 netAmount) storage curr = netDepositedForEpoch[epoch];

                // Pass previous epoch net amount to the next epoch
                // Expired positions are offset, check `participate()`
                curr[sglAssetID] += prev[sglAssetID];
            }
        }
        */
    }

    /// @notice Store the total pool deposited for a given Singularity
    /// @param sglAssetID The Singularity asset ID
    /// @return totalDeposited The total deposited amount in the pool
    function _snapshotTotalDepositedForSgl(uint256 sglAssetID) internal returns (uint256 totalDeposited) {
        /*
        totalDeposited = lastTotalDepositedForSgl[sglAssetID];
        if (block.timestamp > lastTotalDepositRefreshSgl[sglAssetID] + totalDepositRefreshCooldown) {
            (totalDeposited,) = tOLP.getTotalPoolDeposited(sglAssetID);
            lastTotalDepositedForSgl[sglAssetID] = totalDeposited;
            lastTotalDepositRefreshSgl[sglAssetID] = block.timestamp;
        }

        return totalDeposited;
        */
    }
}
