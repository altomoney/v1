// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ITWLBase, Bucket} from "tap-token/interfaces/ITWLBase.sol";

struct Participation {
    uint128 lockedAt; // lock start date
    uint128 expiry; // lock expiration date
    uint128 exerciseDiscountRate; // exercise discount rate
    uint8 bucketId;
    uint256 totalUsdo; // amount of usdo lent
    uint256 tapAmountExercised;
    uint256 lastEpochSync;
    address[] markets;
}

struct PaymentTokenOracle {
    ITapiocaOracle oracle;
    bytes oracleData;
}

interface ITapiocaOptionBroker is ITWLBase {
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
    error EmergencySweepCooldownNotReached();
    error TooHigh();
    error TooLong();
    error TooLow();
    error ExpiredCall();
    error MarketNotActive();

    event Participate(address indexed user, uint256 indexed bucketId, uint256 epoch, uint256 usdoAmount);
    event ExerciseOption(
        address indexed user,
        uint256 indexed epoch,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tapAmount
    );
    event NewEpoch(uint256 indexed epoch, uint256 extractedTap, uint256 epochTapValuation);
    event ExitPosition(
        address indexed user, address indexed to, uint256 indexed bucketId, uint256 epoch, uint256 usdoAmount
    );
    event SetPaymentToken(address indexed paymentToken, address oracle, bytes oracleData);
    event SetTapOracle(address oracle, bytes oracleData);
    event SetPaymentTokenBeneficiary(address paymentTokenBeneficiary);
    event SetCluster(address cluster);
    event Pause(bool pauseState);
    event SetTapOft(address tapOFT);
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();
    event PaymentCollection(address indexed paymentToken, address indexed beneficiary, uint256 amount);
    event SetExerciseWindow(uint256 exerciseWindow);
    event SetMarket(address market, bool active);
    event SetPenrose(address penrose);
    // ==========
    //    READ
    // ==========o

    function getTapToken() external view returns (address);
    function getUSDO() external view returns (address);

    /// @notice Returns the current epoch given a timestamp
    function timestampToEpoch(uint256 timestamp) external view returns (uint256);

    /// @dev Keep compatibility with previous interface
    function getCurrentWeek() external view returns (uint256);

    /// @notice Returns the details of an oTAP position
    /// @param user User address
    /// @param bucketId Bucket ID to check the participation
    /// @return participation
    function getParticipation(address user, uint8 bucketId) external view returns (Participation memory);

    /// @notice Returns the details of an OTC deal
    function getOTCDealDetails(address from, uint256 bucketId, address paymentToken, uint256 buyAmount)
        external
        view
        returns (uint256 eligibleTapAmount, uint256 paymentTokenAmount, uint256 tapAmount);

    // ===========
    //    WRITE
    // ===========

    /// @notice Lock & lend USDO in a singularity market
    /// @param to The user that receives the lent USDO
    /// @param bucketId The bucket ID to use
    /// @param usdoAmount The amount of USDO to lend
    /// @param market The singularity market to lend USDO to
    function lock(address to, uint8 bucketId, uint256 usdoAmount, address market) external;

    /// @notice Exit and unlock lent USDO in all markets if lock is expired
    function unlock(uint8 bucketId, address to) external;

    /// @notice Exit and unlock lent USDO in all markets if user can't lock with debt
    function forceUnlock(uint8 bucketId, address from) external;

    /// @notice Check if a user can lock with debt.
    /// Does account for accrued debt in BigBang markets.
    /// @param user User address
    /// @param amountToLock USDO amount to lock
    /// @return canLock If the user can lock with debt
    /// @return maxLockAmount Maximum USDO the user can lock in this contract
    /// @return mintedUsdoAmount Minted USDO amount in BigBang markets
    function canLockWithDebt(address user, uint256 amountToLock)
        external
        view
        returns (bool canLock, uint256 maxLockAmount, uint256 mintedUsdoAmount);

    /// @notice Exercise an oTAP position
    /// @param bucketId tokenId of the oTAP position, position must be active
    /// @param paymentToken Address of the payment token to use, must be whitelisted
    /// @param tapAmount Amount of TAP to exercise. If 0, the full amount is exercised
    function exerciseOption(uint256 bucketId, address paymentToken, uint256 tapAmount) external;

    /// @notice Start a new epoch, extract TAP from the TapOFT contract,
    ///         emit it to the active singularities and get the price of TAP for the epoch.
    function advanceWeek() external;

    // =========
    //   OWNER
    // =========

    /// @notice Set the TapOFT Oracle address and data
    /// @param tapOracle The new TapOFT Oracle address
    /// @param tapOracleData The new TapOFT Oracle data
    function setTapOracle(address tapOracle, bytes calldata tapOracleData) external;

    /// @notice Set the Penrose address
    /// @param penrose The new Penrose address
    function setPenrose(address penrose) external;

    /// @notice Activate or deactivate a payment token
    /// @dev set the oracle to address(0) to deactivate, expect the same decimal precision as TAP oracle
    function setPaymentToken(address paymentToken, address oracle, bytes calldata oracleData) external;

    /// @notice Set the exercise window
    /// @param exerciseWindow The new exercise window
    function setExerciseWindow(uint256 exerciseWindow) external;

    /// @notice Set the payment token beneficiary
    /// @param paymentTokenBeneficiary The new payment token beneficiary
    function setPaymentTokenBeneficiary(address paymentTokenBeneficiary) external;

    /// @notice Collect the payment tokens from the OTC deals
    /// @param paymentTokens The payment tokens to collect
    function collectPaymentTokens(address[] calldata paymentTokens) external;

    /**
     * @notice updates the Cluster address.
     * @dev can only be called by the owner.
     * @param cluster the new address.
     */
    function setCluster(address cluster) external;

    function collectPenaltyFees() external;

    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool pauseState) external;

    /**
     * @notice Set the emergency sweep cooldown
     */
    function setEmergencySweepCooldown(uint256 _emergencySweepCooldown) external;

    /**
     * @notice Activate the emergency sweep cooldown
     */
    function activateEmergencySweep() external;

    /**
     * @notice Emergency sweep tokens in case of a critical issue, after a cooldown period.
     */
    function emergencySweep(address token) external;

    /**
     * @notice Add a new bucket
     * @param bucket Bucket to add into the system
     */
    function addBucket(Bucket memory bucket) external;

    /**
     * @notice Updates an existing bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system
     * @dev Ignores the lockEpochDuration field.
     */
    function updateBucket(uint8 index, Bucket memory bucket) external;

    /**
     * @notice Set the market active state
     * @param market The market to set the active state
     */
    function setMarket(address market, bool isActive) external;
}
