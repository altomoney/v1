// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca
import {FullMath} from "tap-token/options/FullMath.sol";

import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {TWLBase, Bucket} from "tap-token/governance/TWLBase.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {IBigBang} from "tap-utils/interfaces/bar/IBigBang.sol";
import {ITapiocaOptionBroker, Participation, PaymentTokenOracle} from "tap-token/interfaces/ITapiocaOptionBroker.sol";
/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract TapiocaOptionBroker is ITapiocaOptionBroker, Pausable, Ownable, FullMath, ReentrancyGuard, TWLBase {
    using SafeERC20 for IERC20;

    TapToken public immutable TAP_TOKEN;
    IERC20 public immutable USDO;
    ITapiocaOracle public _tapOracle;
    ICluster public _cluster;
    IPenrose public _penrose;
    address public _paymentTokenBeneficiary; // Where to collect the payment tokens

    uint256 public _epochTAPValuation; // TAP price for the current epoch
    uint256 public _exerciseWindow = 30 days;
    uint256 public _emergencySweepCooldown = 2 days;
    uint256 public _lastEmergencySweep;
    bool public _rescueMode;
    uint256 public _penaltyFeesAccrued;
    uint256 public _minDebtPenalty;
    uint256 public _maxDebtPenalty;
    uint256 public _maxDebtBuffer;

    mapping(address => bool) public _activeMarkets;
    mapping(address => mapping(uint256 => Participation)) public _participations; // accountAddress => bucketId => Participation
    mapping(uint256 => uint256) public _tapPerEpoch; // epoch => availableTAP
    mapping(address => PaymentTokenOracle) public _paymentTokens; // Token address => PaymentTokenOracle
    mapping(uint256 => int256) public _netDepositsPerEpoch; // epoch => total deposited
    mapping(address account => mapping(address marketAddress => uint256 shares)) public _marketShares; // accountAddress => marketAddress => shares
    mapping(address => uint256) public _totalLockedUsdo; // accountAddress => total locked USDO across all markets and buckets

    bytes public _tapOracleData;

    constructor(
        address payable tapOFT,
        address usdo,
        address paymentTokenBeneficiary,
        uint256 epochDuration,
        Bucket[] memory buckets,
        address penrose,
        address admin
    ) TWLBase(epochDuration, buckets) {
        USDO = IERC20(usdo);
        TAP_TOKEN = TapToken(tapOFT);
        _penrose = IPenrose(penrose);
        _paymentTokenBeneficiary = paymentTokenBeneficiary;

        _transferOwnership(admin);
    }

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

    /// @notice Returns the address of the TAP token
    function getTapToken() external view returns (address) {
        return address(TAP_TOKEN);
    }

    /// @notice Returns the address of the USDO token
    function getUSDO() external view returns (address) {
        return address(USDO);
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

    /// @notice Set the delegatee of a participation.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @param _delegatee The address of the delegatee.
    function setDelegatee(uint8 _bucketId, address _delegatee) external {
        _participations[msg.sender][_bucketId].delegatee = _delegatee;

        emit SetDelegatee(msg.sender, _bucketId, _delegatee);
    }

    /// @notice Lock & lend USDO in a singularity market
    /// @param to The user that receives the lent USDO
    /// @param bucketId The bucket ID to use
    /// @param usdoAmount The amount of USDO to lend
    /// @param market The singularity market to lend USDO to
    function lock(address to, uint8 bucketId, uint256 usdoAmount, address market) external whenNotPaused nonReentrant {
        if (lastEpoch != currentEpoch()) revert AdvanceEpochFirst();
        if (usdoAmount == 0) revert AmountNotValid();
        if (_lastEmergencySweep != 0) revert EmergencySweepActivated();
        if (!_activeMarkets[market]) revert MarketNotActive();
        if (to != msg.sender && _participations[to][bucketId].delegatee != msg.sender) revert NotAuthorized();

        (bool canLock,,) = _canLockWithDebt(to, usdoAmount);
        if (!canLock) {
            revert NotAuthorized();
        }

        _supplyInBucket(bucketId, usdoAmount);

        // Create the participation position
        Participation storage position = _participations[to][bucketId];
        Bucket memory bucket = buckets[bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);

        if (position.expiry > 0 && block.timestamp < position.expiry) {
            // Clear the expected votes at the past expected expiration date
            _netDepositsPerEpoch[_timestampToEpoch(position.expiry) + 1] += int256(position.totalUsdo);
        }

        if (block.timestamp > position.expiry) {
            position.tapAmountExercised = 0;
        }

        position.bucketId = bucketId;
        position.totalUsdo += usdoAmount;
        position.exerciseDiscountRate = bucket.rewardsMultiplier;
        position.lockedAt = uint56(block.timestamp);
        position.expiry = uint56(expiry);

        if (_marketShares[to][market] == 0) {
            position.markets.push(market);
        }

        _netDepositsPerEpoch[currentEpoch() + 1] += int256(usdoAmount);
        _netDepositsPerEpoch[_timestampToEpoch(expiry) + 1] -= int256(position.totalUsdo);
        _totalLockedUsdo[to] += usdoAmount;

        IERC20(USDO).safeTransferFrom(msg.sender, address(this), usdoAmount);
        USDO.safeApprove(market, usdoAmount);

        uint256 shares = ISingularity(market).addAsset(address(this), address(this), usdoAmount);
        if (shares == 0) revert SharesNotValid();
        _marketShares[to][market] += shares;
        USDO.safeApprove(market, 0);

        emit Participate(to, bucketId, currentEpoch(), usdoAmount);
    }

    /// @notice Exit and unlock lent USDO in all markets if lock is expired
    function unlock(uint8 bucketId, address to) external whenNotPaused {
        if (to != msg.sender && _participations[to][bucketId].delegatee != msg.sender) revert NotAuthorized();

        Participation storage position = _participations[to][bucketId];

        if (block.timestamp < position.expiry) {
            revert LockNotExpired();
        }

        uint256 totalUsdo = position.totalUsdo;

        position.totalUsdo = 0;

        for (uint256 i; i < position.markets.length; ++i) {
            address market = position.markets[i];
            uint256 shares = _marketShares[to][market];
            delete _marketShares[to][market];

            IERC20(market).safeApprove(market, shares);
            ISingularity(market).removeAsset(address(this), to, shares);
            IERC20(market).safeApprove(market, 0);
        }
        delete position.markets;
        _totalLockedUsdo[to] -= totalUsdo;
        emit ExitPosition(to, to, bucketId, currentEpoch(), totalUsdo);
    }

    /// @notice Exit and unlock lent USDO in all markets if user can't lock with debt
    function forceUnlock(uint8 bucketId, address from) external whenNotPaused {
        // TODO: Add delegate
        Participation storage position = _participations[from][bucketId];

        if (block.timestamp >= position.expiry) {
            revert LockExpired();
        }
        (bool canLock,,) = _canLockWithDebt(from, 0);
        if (canLock) {
            revert NotAuthorized();
        }

        uint256 totalUsdo = position.totalUsdo;

        position.totalUsdo = 0;

        for (uint256 i; i < position.markets.length; ++i) {
            address market = position.markets[i];
            uint256 shares = _marketShares[from][market];
            delete _marketShares[from][market];

            IERC20(market).safeApprove(market, shares);
            uint256 marketUsdoAmount = ISingularity(market).removeAsset(address(this), address(this), shares);
            IERC20(market).safeApprove(market, 0);

            uint256 usdoPenalty =
                _getDebtPenaltyAmount(position.lockedAt, position.expiry - position.lockedAt, marketUsdoAmount);
            _penaltyFeesAccrued += usdoPenalty;
            IERC20(USDO).safeTransfer(from, marketUsdoAmount - usdoPenalty);
        }

        _netDepositsPerEpoch[currentEpoch() + 1] -= int256(totalUsdo);
        _netDepositsPerEpoch[_timestampToEpoch(position.expiry) + 1] += int256(totalUsdo);
        delete position.markets;
        _totalLockedUsdo[from] -= totalUsdo;
        emit ExitPosition(from, from, bucketId, currentEpoch(), totalUsdo);
    }

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
        returns (bool canLock, uint256 maxLockAmount, uint256 mintedUsdoAmount)
    {
        return _canLockWithDebt(user, amountToLock);
    }

    /// @notice Check if a user can lock with debt. Takes into account past locks.
    /// @param user User address
    /// @param amountToLock Amount of USDO to lock
    /// @return canLock If the user can lock with debt
    /// @return maxLockAmount Maximum USDO the user can lock in this contract
    /// @return mintedUsdoAmount Minted USDO amount
    function _canLockWithDebt(address user, uint256 amountToLock)
        internal
        view
        returns (bool canLock, uint256 maxLockAmount, uint256 mintedUsdoAmount)
    {
        mintedUsdoAmount = _getTotalBigBangDebtInUSDO(user);

        maxLockAmount = mintedUsdoAmount + (mintedUsdoAmount * _maxDebtBuffer) / 1e4; // total debt + buffer

        if (maxLockAmount > 0 && amountToLock + _totalLockedUsdo[user] <= maxLockAmount) {
            return (true, maxLockAmount, mintedUsdoAmount);
        }

        return (false, maxLockAmount, mintedUsdoAmount);
    }

    /**
     * @notice Get the USDO total debt of a user in the BigBang markets.
     */
    function _getTotalBigBangDebtInUSDO(address user) internal view returns (uint256 totalUserUsdoDebt) {
        address[] memory markets = _penrose.bigBangMarkets();

        // Loop over the markets, get user debt and sum it
        uint256 len = markets.length;
        for (uint256 i = 0; i < len; i++) {
            IBigBang bigBang = IBigBang(markets[i]);
            Rebase memory totalBorrow = bigBang._totalBorrow();
            uint256 userBorrowPart = bigBang._userBorrowPart(user);
            totalUserUsdoDebt += RebaseLibrary.toElastic(totalBorrow, userBorrowPart, false);
        }
    }

    /// @notice Get the debt penalty amount for a given lock position. Starts at 10% and goes down to 0.5% linearly.
    /// @param lockStartTimestamp Lock start timestamp
    /// @param lockDuration Lock duration
    /// @param lockAmount Lock amount
    /// @return debtPenaltyAmount Debt penalty amount
    function _getDebtPenaltyAmount(uint256 lockStartTimestamp, uint256 lockDuration, uint256 lockAmount)
        internal
        view
        returns (uint256)
    {
        uint256 timePassed = block.timestamp - lockStartTimestamp;
        // If the lock is expired, no penalty
        if (timePassed >= lockDuration) {
            return 0;
        }
        // @dev make sure timePassed is not greater than lockDuration, else it'll underflow
        uint256 penalty = _maxDebtPenalty - ((_maxDebtPenalty - _minDebtPenalty) * timePassed) / lockDuration;
        return (penalty * lockAmount) / 1e4;
    }

    /// @notice Exercise an oTAP position
    /// @param to The address of the user to exercise the option for
    /// @param bucketId tokenId of the oTAP position, position must be active
    /// @param paymentToken Address of the payment token to use, must be whitelisted
    /// @param tapAmount Amount of TAP to exercise. If 0, the full amount is exercised
    function exerciseOption(address to, uint256 bucketId, address paymentToken, uint256 tapAmount) external whenNotPaused {
        if (to != msg.sender && _participations[to][bucketId].delegatee != msg.sender) revert NotAuthorized();
        Participation storage position = _participations[to][bucketId];

        uint256 cachedEpoch = currentEpoch();

        if (!_isPositionActive(position)) {
            cachedEpoch = _timestampToEpoch(position.expiry);
        }

        if (block.timestamp > position.expiry + _exerciseWindow) revert ExpiredCall();

        // Check requirements
        if (address(_paymentTokens[paymentToken].oracle) == address(0)) {
            revert PaymentTokenNotSupported();
        }

        if (lastEpoch < cachedEpoch) revert AdvanceEpochFirst();

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
    function advanceWeek() external onlyOwner {
        if (lastEpoch == currentEpoch()) revert NotValid();
        uint256 epoch = currentEpoch();

        uint256 previousEpoch = lastEpoch;
        _syncTWLBuckets(epoch - lastEpoch);

        // Get epoch TAP valuation
        bool success;
        (success, _epochTAPValuation) = _tapOracle.get(_tapOracleData);
        if (!success) revert Failed();

        // Extract TAP
        uint256 epochTAP = TAP_TOKEN.emitForWeek();
        _tapPerEpoch[epoch] += epochTAP;

        // Pass previous epoch net USDO amount to the next epoch
        while (previousEpoch < epoch) {
            uint40 nextEpoch = uint40(previousEpoch) + 1;
            _netDepositsPerEpoch[nextEpoch] += _netDepositsPerEpoch[previousEpoch];
            ++previousEpoch;
        }

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

    /// @notice Set the max debt buffer
    /// @param maxDebtBuffer The new max debt buffer
    function setMaxDebtBuffer(uint256 maxDebtBuffer) external onlyOwner {
        _maxDebtBuffer = maxDebtBuffer;

        emit SetMaxDebtBuffer(maxDebtBuffer);
    }

    /// @notice Set the Penrose address
    /// @param penrose The new Penrose address
    function setPenrose(address penrose) external onlyOwner {
        _penrose = IPenrose(penrose);
        emit SetPenrose(penrose);
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

    function collectPenaltyFees() external onlyOwner {
        uint256 penaltyFees = _penaltyFeesAccrued;
        _penaltyFeesAccrued = 0;
        IERC20(USDO).safeTransfer(owner(), penaltyFees);
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
     * @notice Set the emergency sweep cooldown
     */
    function setEmergencySweepCooldown(uint256 emergencySweepCooldown) external onlyOwner {
        _emergencySweepCooldown = emergencySweepCooldown;
        emit SetEmergencySweepCooldown(emergencySweepCooldown);
    }

    function enableTapTokenRewards() external onlyOwner {
        TAP_TOKEN.initEmissions();
    }

    /**
     * @notice Activate the emergency sweep cooldown
     */
    function activateEmergencySweep() external onlyOwner {
        _lastEmergencySweep = block.timestamp;
        emit ActivateEmergencySweep();
    }

    /**
     * @notice Emergency sweep tokens in case of a critical issue, after a cooldown period.
     */
    function emergencySweep(address token) external onlyOwner {
        if (_lastEmergencySweep == 0 || block.timestamp < _lastEmergencySweep + _emergencySweepCooldown) {
            revert EmergencySweepCooldownNotReached();
        }

        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Add a new bucket
     * @param bucket Bucket to add into the system
     */
    function addBucket(Bucket memory bucket) external override(ITapiocaOptionBroker, TWLBase) onlyOwner {
        _addBucket(bucket);
    }

    /**
     * @notice Updates an existing bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system
     * @dev Ignores the lockEpochDuration field.
     */
    function updateBucket(uint8 index, Bucket memory bucket)
        external
        override(ITapiocaOptionBroker, TWLBase)
        onlyOwner
    {
        _updateBucket(index, bucket);
    }

    /**
     * @notice Set the market active state
     * @param market The market to set the active state
     */
    function setMarket(address market, bool isActive) external onlyOwner {
        _activeMarkets[market] = isActive;
        emit SetMarket(market, isActive);
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

        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), discountedPaymentAmount);

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
