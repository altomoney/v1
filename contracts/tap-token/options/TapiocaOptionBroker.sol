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
import {ISingularity} from "tap-utils/interfaces/periph/ISingularity.sol";
import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";

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
    uint256 totalUsdo; // amount of usdo lent
    uint256 tapAmountExercised;
    uint256 lastEpochSync;
    address[] singularityMarkets;
    mapping(address singularityMarket => uint256 shares) singularityShares;
}

struct PaymentTokenOracle {
    ITapiocaOracle oracle;
    bytes oracleData;
}

contract TapiocaOptionBroker is Pausable, Ownable, FullMath, ReentrancyGuard, TWLBase {
    using SafeERC20 for IERC20;

    TapToken public immutable TAP_TOKEN;
    address public immutable USDO;
    ITapiocaOracle public _tapOracle;
    ICluster public _cluster;
    address public _paymentTokenBeneficiary; // Where to collect the payment tokens

    uint256 public _epochTAPValuation; // TAP price for the current epoch
    uint256 public _exerciseWindow = 30 days;
    uint256 public _emergencySweepCooldown = 2 days;
    uint256 public _lastEmergencySweep;

    mapping(address => mapping(uint256 => Participation)) public _participations; // accountAddress => bucketId => Participation
    mapping(uint256 => uint256) public _tapPerEpoch; // epoch => availableTAP
    mapping(address => PaymentTokenOracle) public _paymentTokens; // Token address => PaymentTokenOracle
    mapping(uint256 => int256) public _netDepositsPerEpoch; // epoch => total deposited

    bytes public _tapOracleData;

    error NotEqualDurations();
    error NotAuthorized();
    error NoLiquidity();
    error OptionExpired();
    error PaymentTokenNotSupported();
    error OneEpochCooldown();
    error DurationTooShort();
    error PositionNotValid();
    error LockNotExpired();
    error TooSoon();
    error Failed();
    error TransferFailed();
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
    error ExpiredCall();

    constructor(
        address payable tapOFT,
        address usdo,
        address paymentTokenBeneficiary,
        uint256 epochDuration,
        Bucket[] memory buckets,
        address admin
    ) TWLBase(epochDuration, buckets) {
        USDO = usdo;
        TAP_TOKEN = TapToken(tapOFT);
        _paymentTokenBeneficiary = paymentTokenBeneficiary;

        _transferOwnership(admin);
    }

    // ==========
    //   EVENTS
    // ==========
    event Participate(address indexed user, uint256 indexed bucketId, uint256 epoch, uint256 usdoAmount);

    event ExerciseOption(
        address indexed user,
        uint256 indexed epoch,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tapAmount
    );
    event NewEpoch(uint256 indexed epoch, uint256 extractedTap, uint256 epochTapValuation);
    event ExitPosition(address indexed user, uint256 indexed bucketId, uint256 epoch, uint256 usdoAmount);
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
    event SetExerciseWindow(uint256 exerciseWindow);
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
    function getParticipation(address user, uint8 bucketId) external view returns (Participation memory) {
        return _participations[user][bucketId];
    }

    /// @notice Returns the details of an OTC deal
    function getOTCDealDetails(address from, uint256 bucketId, address paymentToken, uint256 buyAmount)
        external
        view
        returns (uint256 eligibleTapAmount, uint256 paymentTokenAmount, uint256 tapAmount)
    {
        // Load data
        Participation memory position = _participations[from][bucketId];

        if (!_isPositionActive(position)) revert OptionExpired();

        uint256 cachedEpoch = currentEpoch();

        PaymentTokenOracle memory paymentTokenOracle = _paymentTokens[paymentToken];

        if (paymentTokenOracle.oracle == ITapiocaOracle(address(0))) {
            revert PaymentTokenNotSupported();
        }

        if (block.timestamp < position.lockedAt + EPOCH_DURATION) {
            revert OneEpochCooldown();
        }

        uint256 netAmount = uint256(_netDepositsPerEpoch[cachedEpoch]);
        if (netAmount == 0) revert NoLiquidity();

        eligibleTapAmount = muldiv(position.totalUsdo, _tapPerEpoch[cachedEpoch], netAmount);
        eligibleTapAmount -= position.tapAmountExercised;
        if (eligibleTapAmount < buyAmount) revert TooHigh();

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

    /// @notice Lock & lend USDO in a singularity market
    function lock(address to, uint8 bucketId, uint256 usdoAmount, address singularityMarket)
        external
        whenNotPaused
        nonReentrant
    {
        if (lastEpoch != currentEpoch()) advanceWeek();
        if (usdoAmount == 0) revert SharesNotValid();
        if (_lastEmergencySweep != 0) revert EmergencySweepActivated();

        _supplyInBucket(bucketId, usdoAmount);

        // Create the participation position
        Participation storage position = _participations[to][bucketId];
        Bucket memory bucket = buckets[bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);

        if (position.expiry > 0 && block.timestamp < position.expiry) {
            // Clear the expected votes at the past expected expiration date
            _netDepositsPerEpoch[_timestampToEpoch(position.expiry) + 1] -= int256(position.totalUsdo);
        }

        if (block.timestamp > position.expiry) {
            position.tapAmountExercised = 0;
        }

        position.bucketId = bucketId;
        position.totalUsdo += usdoAmount;
        position.exerciseDiscountRate = bucket.rewardsMultiplier;
        position.lockedAt = uint56(block.timestamp);
        position.expiry = uint56(expiry);

        if (position.singularityShares[singularityMarket] == 0) {
            position.singularityMarkets.push(singularityMarket);
        }
        USDO.approve(singularityMarket, usdoAmount);

        // Important: Pending to check interface AND token amount after Yieldbox removal task, next line may need to be changed
        position.singularityShares[singularityMarket] +=
            ISingularity(singularityMarket).addAsset(address(this), address(this), false, usdoAmount);
        USDO.approve(singularityMarket, 0);

        _netDepositsPerEpoch[currentEpoch() + 1] += int256(usdoAmount);
        _netDepositsPerEpoch[_timestampToEpoch(expiry) + 1] -= int256(position.totalUsdo);

        IERC20(USDO).safeTransferFrom(msg.sender, address(this), usdoAmount);

        emit Participate(to, bucketId, currentEpoch(), usdoAmount);
    }

    /// @notice Exit and unlock lent USDO in all markets if lock is expired
    function unlock(uint8 bucketId, address to) external whenNotPaused {
        Participation storage position = _participations[msg.sender][bucketId];

        if (block.timestamp < position.expiry) {
            revert LockNotExpired();
        }

        uint256 totalUsdo = position.totalUsdo;

        position.totalUsdo = 0;

        for (uint256 i; i < position.singularityMarkets.length; ++i) {
            address market = position.singularityMarkets[i];
            uint256 shares = position.singularityShares[market];
            delete position.singularityShares[market];

            IERC20(market).approve(market, shares);
            ISingularity(market).removeAsset(address(this), to, shares);
            IERC20(market).approve(market, 0);
        }
        delete position.singularityMarkets;

        emit ExitPosition(msg.sender, bucketId, currentEpoch(), to, totalUsdo);
    }

    /// @notice Exercise an oTAP position
    /// @param bucketId tokenId of the oTAP position, position must be active
    /// @param paymentToken Address of the payment token to use, must be whitelisted
    /// @param tapAmount Amount of TAP to exercise. If 0, the full amount is exercised
    function exerciseOption(uint256 bucketId, address paymentToken, uint256 tapAmount) external whenNotPaused {
        Participation storage position = _participations[msg.sender][bucketId];

        uint256 cachedEpoch = currentEpoch();

        if (!_isPositionActive(position)) {
            cachedEpoch = _timestampToEpoch(position.expiry);
        }

        if (block.timestamp > position.expiry + _exerciseWindow) revert ExpiredCall();

        // Check requirements
        if (address(_paymentTokens[paymentToken].oracle) == address(0)) {
            revert PaymentTokenNotSupported();
        }

        if (_timestampToEpoch(block.timestamp) > cachedEpoch) revert AdvanceEpochFirst();

        if (block.timestamp < position.lockedAt + EPOCH_DURATION) {
            revert OneEpochCooldown();
        }

        // Get eligible OTC amount
        uint256 netAmount = uint256(_netDepositsPerEpoch[cachedEpoch]);
        uint256 eligibleTapAmount = muldiv(position.totalUsdo, _tapPerEpoch[cachedEpoch], netAmount);

        eligibleTapAmount -= position.tapAmountExercised;

        if (eligibleTapAmount < tapAmount) revert TooHigh();

        uint256 chosenAmount = tapAmount == 0 ? eligibleTapAmount : tapAmount;
        if (chosenAmount < 1e18) revert TooLow();
        position.tapAmountExercised += chosenAmount;

        // Finalize the deal
        uint256 paymentAmount = _processOTCDeal(paymentToken, chosenAmount, position.exerciseDiscountRate);

        emit ExerciseOption(msg.sender, cachedEpoch, paymentToken, paymentAmount, chosenAmount);
    }

    /// @notice Start a new epoch, extract TAP from the TapOFT contract,
    ///         emit it to the active singularities and get the price of TAP for the epoch.
    function advanceWeek() public {
        if (lastEpoch == currentEpoch()) revert NotValid();
        uint256 epoch = currentEpoch();

        _syncTWLBuckets(epoch - lastEpoch);

        // Get epoch TAP valuation
        bool success;
        (success, _epochTAPValuation) = _tapOracle.get(_tapOracleData);
        if (!success) revert Failed();

        // Extract TAP
        uint256 epochTAP = TAP_TOKEN.emitForWeek();
        _tapPerEpoch[epoch] += epochTAP;

        // Pass previous epoch net USDO amount to the next epoch
        _netDepositsPerEpoch[epoch] += _netDepositsPerEpoch[epoch - 1];

        lastEpoch = epoch;
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

    /// @notice Set the exercise window
    /// @param exerciseWindow The new exercise window
    function setExerciseWindow(uint256 exerciseWindow) external onlyOwner {
        _exerciseWindow = exerciseWindow;
        emit SetExerciseWindow(exerciseWindow);
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
}
