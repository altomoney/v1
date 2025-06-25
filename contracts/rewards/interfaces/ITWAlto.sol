// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Tapioca

import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {ITWLBase, Bucket} from "./ITWLBase.sol";

struct Participation {
    // 1 slot
    uint8 bucketId;
    bool tapReleased; // allow restaking while rewards may still accumulate
    uint240 lockedAt; // timestamp when lock was created
    // 1 slot
    uint56 expiry; // expiry timestamp.
    uint88 tapAmount; // amount of TAP locked
    uint24 multiplier; // Votes = multiplier * tapAmount
    uint40 lastInactive; // One week BEFORE the staker gets a share of rewards
    uint40 lastActive; // Last week that the staker shares in rewards
    address delegatee; // The delegatee of the locker to claim rewards on their behalf
}

struct Reward {
    uint256 pending;
    uint256 claimed;
}

interface ITWAlto is ITWLBase {
    // ==========
    //    READ
    // ==========

    /// @notice Returns the current epoch number
    /// @dev keeps compatibility with older interface
    function currentWeek() external view returns (uint256);

    /// @notice Returns the init timestamp
    /// @dev keeps compatibility with older interface
    function creation() external view returns (uint256);

    /// @notice Return the participation of an account in a bucket.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return participation The Participation of the account in the bucket.
    function getParticipation(address _account, uint256 _bucketId)
        external
        view
        returns (Participation memory participation);

    /// @notice Return the Participation of a token and the claimable amounts.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return position The Participation of the token.
    function getPosition(address _account, uint256 _bucketId) external view returns (Participation memory position);

    /// @notice Participate in twAML voting and mint an twTap position in a lock bucket.
    ///
    /// @param _participant The address of the participant
    /// @param _amount The amount of TAP to participate with
    /// @param _bucketId The lock bucket id
    function participate(address _participant, uint256 _amount, uint8 _bucketId) external;

    /// @notice Reuse an expired participation to participate again in twAML voting and mint an twTap position in a lock bucket.
    /// @param _bucketId The new lock bucket id to migrate the position from the expired participation in a new participation
    function reuseParticipation(address _participant, uint8 _bucketId) external;

    /**
     * @notice Exit a twAML participation, delete the voting power if existing and send the TAP to `_to`.
     * @param _participant The address of the participant.
     * @param _bucketId The bucketId of the twTAP position.
     * @param _to The address to send the TAP to.
     * @return tapAmount_ The amount of TAP released.
     */
    function exitPosition(address _participant, address _to, uint256 _bucketId) external returns (uint256 tapAmount_);

    /// @notice Indicate that (a) week(s) have passed and update running totals
    /// @notice Reverts if called in week 0. Let it.
    /// @param _limit Maximum number of weeks to process in one call
    function advanceWeek(uint256 _limit) external;

    /// @notice Set the delegatee of a participation.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @param _delegatee The address of the delegatee.
    function setDelegatee(uint256 _bucketId, address _delegatee) external;

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

    function altoToken() external view returns (AltoToken);
}
