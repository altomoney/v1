// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca

import {TWLBase, Bucket} from "./TWLBase.sol";
import {ITWTAPv2, Participation, Reward, WeekTotals} from "./interfaces/ITWTAPv2.sol";

contract TwTAP is ITWTAPv2, TWLBase, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    TapToken public immutable tapOFT;

    mapping(address => mapping(uint256 => Participation)) public participations; // accountAddress => bucketId => Participation

    uint256 constant DIST_PRECISION = 2 ** 128; //2 ** 128;

    IERC20[] public rewardTokens;
    mapping(IERC20 => uint256) public rewardTokenIndex; // Index 0 is reserved with 0x0 address
    uint256 public maxRewardTokens;

    // account -> bucketId -> rewardTokens index -> amount
    mapping(address => mapping(uint256 => mapping(uint256 => Reward))) public rewards;

    // The current week is determined by creation, but there are values that
    // need to be updated weekly. If, for any reason whatsoever, this cannot
    // be done in time, the `lastProcessedWeek` will be behind until this is
    // done.
    uint256 public lastProcessedWeek;
    mapping(uint256 => uint256) public weekTotals;

    bool public rescueMode;
    uint256 public emergencySweepCooldown = 2 days;
    uint256 public lastEmergencySweep;

    uint256 constant MULTIPLIER_PRECISION = 1e18;

    constructor(address _tapOFT, address _owner, uint256 epochDuration, Bucket[] memory _buckets)
        TWLBase(epochDuration, _buckets)
        Ownable(_owner)
    {
        tapOFT = TapToken(_tapOFT);
    }

    // ==========
    //    READ
    // ==========

    /// @notice Returns the current epoch number
    /// @dev keeps compatibility with older interface
    function currentWeek() external view returns (uint256) {
        return currentEpoch();
    }

    /// @notice Returns the init timestamp
    /// @dev keeps compatibility with older interface
    function creation() external view returns (uint256) {
        return INIT_TIMESTAMP;
    }

    /// @notice Return the total amount distributed for a reward token in a given week.
    /// @param _week The week to query.
    /// @param _rewardTokenId The reward token to query.
    /// @return The total amount distributed for the reward token in the given week.
    function getTotalDistPerVoteForWeek(uint256 _week, uint256 _rewardTokenId) external view returns (uint256) {
        return weekTotals[_week].totalDistPerVote[_rewardTokenId];
    }

    /// @notice Return the participation of an account in a bucket.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return participation The Participation of the account in the bucket.
    function getParticipation(address _account, uint256 _bucketId)
        external
        view
        returns (Participation memory participation)
    {
        return participations[_account][_bucketId];
    }

    /// @notice Return the Participation of a token and the claimable amounts.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return position The Participation of the token.
    /// @return claimables The claimable amounts of each reward token.
    function getPosition(address _account, uint256 _bucketId) external view returns (Participation memory position) {
        position = participations[_account][_bucketId];
    }

    // ===========
    //    WRITE
    // ===========

    /// @notice Participate in twAML voting and mint an twTap position in a lock bucket.
    ///
    /// @param _participant The address of the participant
    /// @param _amount The amount of TAP to participate with
    /// @param _bucketId The lock bucket id
    function participate(address _participant, uint256 _amount, uint8 _bucketId) external whenNotPaused nonReentrant {
        Participation memory position = participations[_participant][_bucketId];
        if (_participant != msg.sender && position.delegatee != msg.sender) revert NotAuthorized();
        _participate(_participant, _amount, _bucketId, true);
    }

    /// @notice Reuse an expired participation to participate again in twAML voting and mint an twTap position in a lock bucket.
    /// @param _bucketId The new lock bucket id to migrate the position from the expired participation in a new participation
    function reuseParticipation(address _participant, uint8 _bucketId) external whenNotPaused nonReentrant {
        Participation memory position = participations[_participant][_bucketId];
        if (_participant != msg.sender && position.delegatee != msg.sender) revert NotAuthorized();
        if (position.tapReleased) revert NotValid();
        if (position.tapAmount == 0) revert NotValid();

        _participate(_participant, position.tapAmount, _bucketId, false);
    }

    /**
     * @notice Exit a twAML participation, delete the voting power if existing and send the TAP to `_to`.
     * @param _bucketId The bucketId of the twTAP position.
     * @return releasedAmount The amount of TAP released.
     */
    function exitPosition(address _participant, address _to, uint256 _bucketId)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 releasedAmount)
    {
        Participation memory position = participations[_participant][_bucketId];
        if (_participant != msg.sender && position.delegatee != msg.sender) revert NotAuthorized();

        // If in rescue mode, allow the release of the TAP even if the lock has not expired.
        if (!rescueMode) {
            if (position.expiry > block.timestamp) revert LockNotExpired();
        }

        if (position.tapReleased) {
            return 0;
        }

        releasedAmount = position.tapAmount;

        participations[_participant][_bucketId].tapReleased = true;
        participations[_participant][_bucketId].tapAmount = 0;
        participations[_participant][_bucketId].expiry = 0;

        tapOFT.transfer(_to, releasedAmount);
        emit ExitPosition(_bucketId, _to, releasedAmount);
    }

    /// @notice Indicate that (a) week(s) have passed and update running totals
    /// @notice Reverts if called in week 0. Let it.
    /// @param _limit Maximum number of weeks to process in one call
    function advanceWeek(uint256 _limit) public nonReentrant {
        _advanceWeek(_limit);
    }

    /// @notice Set the delegatee of a participation.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @param _delegatee The address of the delegatee.
    function setDelegatee(uint256 _bucketId, address _delegatee) external {
        participations[msg.sender][_bucketId].delegatee = _delegatee;

        emit NewDelegate(msg.sender, _bucketId, _delegatee);
    }

    // =========
    //   OWNER
    // =========
    /**
     * @notice Set the rescue mode.
     */
    function setRescueMode(bool _rescueMode) external onlyOwner {
        emit RescueMode(_rescueMode);
        rescueMode = _rescueMode;
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

    /**
     * @notice Emergency sweep of all tokens in case of a critical issue, after a cooldown period.
     * @dev Strategy is to sweep tokens, then recreate positions with them on a new contract.
     *
     */
    function emergencySweep(address token) external onlyOwner {
        if (lastEmergencySweep == 0 || block.timestamp < lastEmergencySweep + emergencySweepCooldown) {
            revert EmergencySweepCooldownNotReached();
        }
        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Adds a new locking bucket
     * @param bucket The bucket to add
     */
    function addBucket(Bucket memory bucket) external override(ITWTAPv2, TWLBase) onlyOwner {
        _addBucket(bucket);
    }

    /**
     * @notice Updates a bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket struct to update, ignores lockEpochDuration field
     */
    function updateBucket(uint8 index, Bucket memory bucket) external override(ITWTAPv2, TWLBase) onlyOwner {
        _updateBucket(index, bucket);
    }

    // ============
    //   INTERNAL
    // ============
    function _timestampToEpoch(uint256 timestamp) internal view returns (uint256) {
        return ((timestamp - INIT_TIMESTAMP) / EPOCH_DURATION);
    }

    /// @dev Internal function to participate in twAML voting and mint an twTap position in a lock bucket.
    /// @param _participant The address of the participant
    /// @param _amount The amount of TAP to participate with. Max uint88.
    /// @param _bucketId The lock bucket id
    /// @param _transferFrom Whether to transfer the TAP from the participant to the contract, or not due is a reuse of a participation
    function _participate(address _participant, uint256 _amount, uint8 _bucketId, bool _transferFrom) internal {
        if (_amount == 0) revert NotValid();
        if (rescueMode) revert RescueModeActive();
        if (lastEmergencySweep != 0) revert EmergencySweepActivated();
        if (_amount > type(uint88).max) {
            revert SafeCastOverflowedUintDowncast(88, _amount);
        }
        if (lastProcessedWeek != currentEpoch()) _advanceWeek(currentEpoch() - lastProcessedWeek);

        if (_transferFrom) {
            IERC20(address(tapOFT)).safeTransferFrom(_participant, address(this), _amount);
        }

        _supplyInBucket(_bucketId, _amount);

        Participation storage position = participations[_participant][_bucketId];
        Bucket memory bucket = buckets[_bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);
        uint40 w0 = uint40(currentEpoch());
        uint40 w1 = uint40(_timestampToEpoch(expiry));

        if (position.expiry > 0 && block.timestamp < position.expiry) {
            // Clear the expected votes at the past expected expiration date
            weekTotals[currentEpoch() + 1].netActiveVotes -= int256(uint256(position.tapAmount) * position.multiplier);
            weekTotals[_timestampToEpoch(position.expiry) + 1].netActiveVotes +=
                int256(uint256(position.tapAmount) * position.multiplier);
        }

        position.bucketId = _bucketId;
        position.tapReleased = false;
        position.lockedAt = uint56(block.timestamp);
        position.expiry = uint56(expiry);
        position.tapAmount = position.tapAmount + uint88(_amount);
        position.multiplier = bucket.rewardsMultiplier;
        position.lastInactive = w0;
        position.lastActive = w1;

        weekTotals[w0 + 1].netActiveVotes += int256(uint256(position.tapAmount) * bucket.rewardsMultiplier);
        weekTotals[w1 + 1].netActiveVotes -= int256(uint256(position.tapAmount) * bucket.rewardsMultiplier);

        emit Participate(_participant, _bucketId, _amount, bucket.rewardsMultiplier, expiry, _bucketId);
    }

    function _advanceWeek(uint256 _limit) internal {
        if (_limit == 0) revert NotValid();
        if (lastProcessedWeek == currentEpoch()) revert NotValid();

        uint256 week = lastProcessedWeek;
        uint256 goal = currentEpoch();

        if (goal - week > _limit) {
            goal = week + _limit;
        }
        uint256 pendingEpochs = goal - week;

        while (week < goal) {
            uint256 prev = weekTotals[week];
            uint256 next = weekTotals[++week];

            next += prev;
        }

        // Sync TWL Buckets
        _syncTWLBuckets(_limit);

        lastProcessedWeek = goal;

        emit AdvanceEpoch(goal, lastProcessedWeek);
    }
}
