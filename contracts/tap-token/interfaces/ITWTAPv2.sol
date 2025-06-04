// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Tapioca

import {ICluster} from "tap-utils/interfaces/common/ICluster.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {ITWLBase, Bucket} from "tap-token/interfaces/ITWLBase.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

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

struct WeekTotals {
    // For [0..currentWeek] this is a cumulative total: it consists of the
    // active votes in the previous week, minus the votes known to expire this
    // week. For future weeks, it is a negative number corresponding to the
    // expiring votes.
    int256 netActiveVotes;
    // rewardTokens index -> amount
    mapping(uint256 => uint256) totalDistPerVote;
}

interface ITWTAPv2 is ITWLBase {
    error NotAuthorized();
    error AdvanceWeekFirst();
    error NotValid();
    error Registered();
    error TokenLimitReached();
    error NotApproved(uint256 tokenId, address spender);
    error LockNotExpired();
    error DurationNotMultiple(); // Lock duration should be a multiple of 1 EPOCH
    error EmergencySweepCooldownNotReached();
    error RescueModeActive();
    error EmergencySweepActivated();

    event AddRewardToken(address indexed rewardTokenAddress, uint256 rewardTokenIndex);
    event DistributeReward(
        address indexed rewardTokenAddress, address indexed from, uint256 amount, uint256 rewardTokenIndex
    );

    event ClaimReward(
        address indexed rewardTokenAddress,
        address indexed to,
        uint256 indexed twTapTokenId,
        uint256 amount,
        uint256 rewardTokenIndex
    );
    event Participate(
        address indexed participant,
        uint256 mintedTokenId,
        uint256 tapAmount,
        uint256 multiplier,
        uint256 expiry,
        uint256 bucketId
    );
    event ExitPosition(uint256 indexed twTapTokenId, address indexed releasedTo, uint256 amount);
    event NewDelegate(address indexed participant, uint256 indexed bucketId, address indexed delegatee);

    event LogMaxRewardsLength(uint256 _oldLength, uint256 _newLength, uint256 _currentLength);
    event RescueMode(bool _rescueMode);
    event SetCluster(address _cluster);
    event EmergencySweepLocks();
    event EmergencySweepRewards();
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();
    event SetTapOft(address tapOFT);

    // ==========
    //    READ
    // ==========

    /// @notice Get the reward tokens list
    /// @return The reward tokens list
    function getRewardTokens() external view returns (IERC20[] memory);

    /// @notice Get the index of a reward token
    /// @param _token The address of the reward token
    /// @return The index of the reward token
    function rewardTokenIndex(IERC20 _token) external view returns (uint256);

    /// @notice Returns the current epoch number
    /// @dev keeps compatibility with older interface
    function currentWeek() external view returns (uint256);

    /// @notice Returns the init timestamp
    /// @dev keeps compatibility with older interface
    function creation() external view returns (uint256);

    /// @notice Return the total amount distributed for a reward token in a given week.
    /// @param _week The week to query.
    /// @param _rewardTokenId The reward token to query.
    /// @return The total amount distributed for the reward token in the given week.
    function getTotalDistPerVoteForWeek(uint256 _week, uint256 _rewardTokenId) external view returns (uint256);

    /// @notice Return the participation of an account in a bucket.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return participation The Participation of the account in the bucket.
    function getParticipation(address _account, uint256 _bucketId)
        external
        view
        returns (Participation memory participation);

    /**
     * @notice Amount currently claimable for each reward token.
     * @dev index 0 will ALWAYS return 0, as it's used by address(0x0).
     * @dev Safe to claim even after position exit.
     * @return claimable amounts mapped by reward token
     */
    function claimable(address _account, uint256 _bucketId) external view returns (uint256[] memory);

    /// @notice Return the Participation of a token and the claimable amounts.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return position The Participation of the token.
    /// @return claimables The claimable amounts of each reward token.
    function getPosition(address _account, uint256 _bucketId)
        external
        view
        returns (Participation memory position, uint256[] memory claimables);

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
     * @notice claims all rewards distributed since token mint or last claim.
     *
     * @param _bucketId bucket Id whose rewards to claim
     *
     * @return amounts_ Claimed amount of each reward token.
     */
    function claimRewards(address _participant, uint256 _bucketId) external returns (uint256[] memory amounts_);

    /**
     * @notice batch claims all rewards distributed since token mint or last claim.
     *
     * @param _bucketIds The lock bucket ids whose rewards to claim
     *
     * @return amounts_ Claimed amountsof each reward token, for each bucketId
     */
    function batchClaimRewards(address _participant, uint256[] calldata _bucketIds)
        external
        returns (uint256[][] memory amounts_);

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

    /// @notice distributes a reward among all tokens, weighted by voting power
    /// @notice The reward gets allocated to all positions that have locked in
    /// @notice the current week. Fails, intentionally, if this number is zero.
    /// @notice Total rewards cannot exceed 2^128 tokens.
    /// @param _rewardTokenId index of the reward in `rewardTokens`
    /// @param _amount amount of reward token to distribute.
    function distributeReward(uint256 _rewardTokenId, uint256 _amount) external;
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
     * @notice Set the maximum number of reward tokens.
     * @param _length The new maximum number of reward tokens.
     */
    function setMaxRewardTokensLength(uint256 _length) external;

    /**
     * @notice Add a reward token to the list of reward tokens.
     * @param _token The address of the reward token.
     */
    function addRewardToken(IERC20 _token) external returns (uint256);

    /**
     * @notice updates the Cluster address.
     * @dev can only be called by the owner.
     * @param _cluster the new address.
     */
    function setCluster(ICluster _cluster) external;

    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool _pauseState) external;

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

    function tapOFT() external view returns (TapToken);
}
