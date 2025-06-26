// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITWLBase, Bucket} from "./ITWLBase.sol";

struct Participation {
    uint8 bucketId;
    uint64 multiplier; // Votes = multiplier * lockAmount
    uint256 lockedAt; // timestamp when lock was created
    uint256 expiry; // expiry timestamp.
    uint256 lockAmount; // amount of lock token locked
}

interface ITWAlto is ITWLBase {
    // ==========
    //    READ
    // ==========

    /// @notice Return the participation of an account in a bucket.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twAlto position.
    /// @return participation The Participation of the account in the bucket.
    function getParticipation(address _account, uint256 _bucketId)
        external
        view
        returns (Participation memory participation);

    /// @notice Participate in twAML voting and mint an twAlto position in a lock bucket.
    ///
    /// @param _participant The address of the participant
    /// @param _amount The amount of lock token to participate with
    /// @param _bucketId The lock bucket id
    function participate(address _participant, uint256 _amount, uint8 _bucketId) external;

    /// @notice Reuse an expired participation to participate again in twAML voting and mint an twAlto position in a lock bucket.
    /// @param _bucketId The new lock bucket id to migrate the position from the expired participation in a new participation
    function reuseParticipation(address _participant, uint8 _bucketId) external;

    /**
     * @notice Exit a twAML participation, delete the voting power if existing and send the lock token to `_to`.
     * @param _participant The address of the participant.
     * @param _bucketId The bucketId of the twAlto position.
     * @param _to The address to send the lock token to.
     * @return releasedAmount The amount of lock token released.
     */
    function exitPosition(address _participant, address _to, uint256 _bucketId) external returns (uint256);

    /// @notice Indicate that (a) epoch(s) have passed and update running totals
    /// @notice Reverts if called in epoch 0. Let it.
    /// @param _limit Maximum number of epochs to process in one call
    function advanceEpoch(uint256 _limit) external;

    // =========
    //   OWNER
    // =========
    /**
     * @notice Set the rescue mode.
     */
    function setRescueMode(bool _rescueMode) external;

    /**
     * @notice Set the emergency sweep cooldown
     */
    function setEmergencySweepCooldown(uint256 _emergencySweepCooldown) external;
    /**
     * @notice Activate the emergency sweep cooldown
     */
    function activateEmergencySweep() external;
    /**
     * @notice Emergency sweep of all tokens in case of a critical issue, after a cooldown period.
     * @dev Strategy is to sweep tokens, then recreate positions with them on a new contract.
     *
     */
    function emergencySweep(address token) external;

    /**
     * @notice Adds a new locking bucket
     * @param bucket The bucket to add
     */
    function addBucket(Bucket memory bucket) external;

    /**
     * @notice Updates a bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket struct to update, ignores lockEpochDuration field
     */
    function updateBucket(uint8 index, Bucket memory bucket) external;

    function lockToken() external view returns (address);
}
