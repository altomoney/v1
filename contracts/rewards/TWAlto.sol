// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Pausable} from "@alto/utils/Pausable.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {TWLBase, Bucket} from "./TWLBase.sol";
import {ITWAlto, Participation} from "./interfaces/ITWAlto.sol";
import {TWAltoErrorsLib} from "./libraries/TWAltoErrorsLib.sol";
import {TWAltoEventsLib} from "./libraries/TWAltoEventsLib.sol";

bytes32 constant PAUSE_TYPE = keccak256("PAUSE");

contract TWAlto is ITWAlto, TWLBase, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    address public immutable lockToken;

    mapping(address => mapping(uint256 => Participation)) public participations; // accountAddress => bucketId => Participation

    // The current epoch is determined by creation, but there are values that
    // need to be updated every epoch. If, for any reason whatsoever, this cannot
    // be done in time, the `lastProcessedEpoch` will be behind until this is
    // done.
    uint256 public lastProcessedEpoch;

    bool public rescueMode;
    uint256 public emergencySweepCooldown = 2 days;
    uint256 public lastEmergencySweep;

    constructor(address _lockToken, address admin, uint256 epochDuration, Bucket[] memory _buckets)
        TWLBase(epochDuration, _buckets)
        Ownable(admin)
    {
        lockToken = _lockToken;
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status) external override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }

    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    // ==========
    //    READ
    // ==========

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

    // ===========
    //    WRITE
    // ===========

    /// @notice Participate in twAML voting and mint an twTap position in a lock bucket.
    ///
    /// @param _participant The address of the participant
    /// @param _amount The amount of TAP to participate with
    /// @param _bucketId The lock bucket id
    function participate(address _participant, uint256 _amount, uint8 _bucketId) external whenNotPaused nonReentrant {
        if (_participant != msg.sender) revert TWAltoErrorsLib.NotAuthorized();
        _participate(_participant, _amount, _bucketId, true);
    }

    /// @notice Reuse an expired participation to participate again in twAML voting and mint an twTap position in a lock bucket.
    /// @param _bucketId The new lock bucket id to migrate the position from the expired participation in a new participation
    function reuseParticipation(address _participant, uint8 _bucketId) external whenNotPaused nonReentrant {
        Participation memory position = participations[_participant][_bucketId];
        if (_participant != msg.sender) revert TWAltoErrorsLib.NotAuthorized();
        if (position.lockAmount == 0) revert TWAltoErrorsLib.NotValid();

        _participate(_participant, position.lockAmount, _bucketId, false);
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
        if (_participant != msg.sender) revert TWAltoErrorsLib.NotAuthorized();
        if (position.lockAmount == 0) revert TWAltoErrorsLib.NotValid();

        // If in rescue mode, allow the release of the TAP even if the lock has not expired.
        if (!rescueMode) {
            if (position.expiry > block.timestamp) revert TWAltoErrorsLib.LockNotExpired();
        }

        releasedAmount = position.lockAmount;

        participations[_participant][_bucketId].lockAmount = 0;
        participations[_participant][_bucketId].expiry = 0;

        IERC20(lockToken).transfer(_to, releasedAmount);
        emit TWAltoEventsLib.ExitPosition(_bucketId, _to, releasedAmount);
    }

    /// @inheritdoc ITWAlto
    function advanceEpoch(uint256 _limit) external {
        _advanceEpoch(_limit);
    }

    // =========
    //   OWNER
    // =========
    /**
     * @notice Set the rescue mode.
     */
    function setRescueMode(bool _rescueMode) external onlyOwner {
        emit TWAltoEventsLib.RescueMode(_rescueMode);
        rescueMode = _rescueMode;
    }

    /**
     * @notice Set the emergency sweep cooldown
     */
    function setEmergencySweepCooldown(uint256 _emergencySweepCooldown) external onlyOwner {
        emergencySweepCooldown = _emergencySweepCooldown;
        emit TWAltoEventsLib.SetEmergencySweepCooldown(_emergencySweepCooldown);
    }

    /**
     * @notice Activate the emergency sweep cooldown
     */
    function activateEmergencySweep() external onlyOwner {
        lastEmergencySweep = block.timestamp;
        emit TWAltoEventsLib.ActivateEmergencySweep();
    }

    /**
     * @notice Emergency sweep of all tokens in case of a critical issue, after a cooldown period.
     * @dev Strategy is to sweep tokens, then recreate positions with them on a new contract.
     *
     */
    function emergencySweep(address token) external onlyOwner {
        if (lastEmergencySweep == 0 || block.timestamp < lastEmergencySweep + emergencySweepCooldown) {
            revert TWAltoErrorsLib.EmergencySweepCooldownNotReached();
        }
        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Adds a new locking bucket
     * @param bucket The bucket to add
     */
    function addBucket(Bucket memory bucket) external override(ITWAlto, TWLBase) onlyOwner {
        _addBucket(bucket);
    }

    /**
     * @notice Updates a bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket struct to update, ignores lockEpochDuration field
     */
    function updateBucket(uint8 index, Bucket memory bucket) external override(ITWAlto, TWLBase) onlyOwner {
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
    /// @param _amount The amount of TAP to participate with.
    /// @param _bucketId The lock bucket id
    /// @param _transferFrom Whether to transfer the TAP from the participant to the contract, or not due is a reuse of a participation
    function _participate(address _participant, uint256 _amount, uint8 _bucketId, bool _transferFrom) internal {
        if (_amount == 0) revert TWAltoErrorsLib.NotValid();
        if (rescueMode) revert TWAltoErrorsLib.RescueModeActive();
        if (lastEmergencySweep != 0) revert TWAltoErrorsLib.EmergencySweepActivated();
        if (lastProcessedEpoch != currentEpoch()) _advanceEpoch(currentEpoch() - lastProcessedEpoch);

        if (_transferFrom) {
            IERC20(lockToken).safeTransferFrom(_participant, address(this), _amount);
        }

        _supplyInBucket(_bucketId, _amount);

        Participation storage position = participations[_participant][_bucketId];
        Bucket memory bucket = buckets[_bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);

        position.bucketId = _bucketId;
        position.lockedAt = block.timestamp;
        position.expiry = expiry;
        position.lockAmount = position.lockAmount + _amount;
        position.multiplier = bucket.rewardsMultiplier;

        emit TWAltoEventsLib.Participate(_participant, _bucketId, _amount, bucket.rewardsMultiplier, expiry);
    }

    function _advanceEpoch(uint256 _limit) internal {
        if (_limit == 0) revert TWAltoErrorsLib.NotValid();
        if (lastProcessedEpoch == currentEpoch()) revert TWAltoErrorsLib.NotValid();

        uint256 epoch = lastProcessedEpoch;
        uint256 goal = currentEpoch();

        if (goal - epoch > _limit) {
            goal = epoch + _limit;
        }

        // Sync TWL Buckets
        _syncTWLBuckets(_limit);

        lastProcessedEpoch = goal;

        emit AdvanceEpoch(goal, lastProcessedEpoch);
    }
}
