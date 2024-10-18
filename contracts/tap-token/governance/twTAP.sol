// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca
import {IPearlmit, PearlmitHandler} from "tap-utils/pearlmit/PearlmitHandler.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {TWLBase, Bucket} from "tap-token/governance/TWLBase.sol";
import {ITWTAPv2, Participation, Reward, WeekTotals} from "tap-token/interfaces/ITWTAPv2.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/**
 * @title TwTAP
 * @author Tapioca
 */
contract TwTAP is ITWTAPv2, TWLBase, Ownable, PearlmitHandler, ReentrancyGuard, Pausable {
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
    uint256 public mintedTWTap;
    uint256 public lastProcessedWeek;
    mapping(uint256 => WeekTotals) public weekTotals;

    ICluster public cluster;

    bool public rescueMode;
    uint256 public emergencySweepCooldown = 2 days;
    uint256 public lastEmergencySweep;

    uint256 constant MULTIPLIER_PRECISION = 1e18;

    constructor(
        address payable _tapOFT,
        IPearlmit _pearlmit,
        address _owner,
        uint256 epochDuration,
        Bucket[] memory _buckets
    ) PearlmitHandler(_pearlmit) TWLBase(epochDuration, _buckets) {
        tapOFT = TapToken(_tapOFT);
        rewardTokens.push(IERC20(address(0x0))); // 0 index is reserved
        maxRewardTokens = 30;

        _transferOwnership(_owner);
    }

    // ==========
    //    READ
    // ==========

    /**
     * @notice Return the address of reward tokens.
     */
    function getRewardTokens() external view returns (IERC20[] memory) {
        return rewardTokens;
    }

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

    /**
     * @notice Amount currently claimable for each reward token.
     * @dev index 0 will ALWAYS return 0, as it's used by address(0x0).
     * @dev Safe to claim even after position exit.
     * @return claimable amounts mapped by reward token
     */
    function claimable(address _account, uint256 _bucketId) public view returns (uint256[] memory) {
        uint256 len = rewardTokens.length;
        uint256[] memory result = new uint256[](len);

        Participation memory position = participations[_account][_bucketId];
        uint256 votes = uint256(position.tapAmount) * uint256(position.multiplier);

        if (votes == 0) {
            return result;
        }

        // If the "last processed week" is behind the actual week, rewards
        // get processed as if it were earlier.
        uint256 week = lastProcessedWeek;
        if (week <= position.lastInactive) {
            return result;
        }
        if (position.lastActive < week) {
            week = position.lastActive;
        }

        WeekTotals storage cur = weekTotals[week];
        WeekTotals storage prev = weekTotals[position.lastInactive];

        for (uint256 i; i < len; i++) {
            Reward memory reward = rewards[_account][_bucketId][i];
            uint256 net = cur.totalDistPerVote[i] - prev.totalDistPerVote[i];
            result[i] = ((votes * net) / DIST_PRECISION) + reward.pending - reward.claimed;
        }
        return result;
    }

    /// @notice Return the Participation of a token and the claimable amounts.
    /// @param _account The account of the participant.
    /// @param _bucketId The bucketId of the twTAP position.
    /// @return position The Participation of the token.
    /// @return claimables The claimable amounts of each reward token.
    function getPosition(address _account, uint256 _bucketId)
        external
        view
        returns (Participation memory position, uint256[] memory claimables)
    {
        position = participations[_account][_bucketId];
        claimables = claimable(_account, _bucketId);
    }

    // ===========
    //    WRITE
    // ===========

    /// @notice Participate in twAML voting and mint an twTap position in a lock bucket.
    /// @dev Requires a Pearlmit approval for the TAP amount
    ///
    /// @param _participant The address of the participant
    /// @param _amount The amount of TAP to participate with
    /// @param _bucketId The lock bucket id
    function participate(address _participant, uint256 _amount, uint8 _bucketId) external whenNotPaused nonReentrant {
        _participate(_participant, _amount, _bucketId, true);
    }

    /// @notice Reuse an expired participation to participate again in twAML voting and mint an twTap position in a lock bucket.
    /// @param _bucketId The new lock bucket id to migrate the position from the expired participation in a new participation
    function reuseParticipation(address _participant, uint8 _bucketId) external whenNotPaused nonReentrant {
        Participation memory position = participations[_participant][_bucketId];
        if (_participant != msg.sender || position.delegatee != msg.sender) revert NotAuthorized();
        if (position.tapReleased) revert NotValid();
        if (position.tapAmount == 0) revert NotValid();

        _participate(_participant, position.tapAmount, _bucketId, false);
    }

    /**
     * @notice claims all rewards distributed since token mint or last claim.
     *
     * @param _bucketId bucket Id whose rewards to claim
     *
     * @return amounts_ Claimed amount of each reward token.
     */
    function claimRewards(address _participant, uint256 _bucketId)
        external
        nonReentrant
        whenNotPaused
        returns (uint256[] memory amounts_)
    {
        Participation memory position = participations[_participant][_bucketId];
        if (_participant != msg.sender || position.delegatee != msg.sender) revert NotAuthorized();
        amounts_ = _claimBucketRewards(_participant, _bucketId, true);
    }

    /**
     * @notice claims all rewards distributed since token mint or last claim.
     *
     * @param _bucketId bucket Id whose rewards to claim
     *
     * @return amounts_ Claimed amount of each reward token.
     */
    function claimRewards(uint256 _bucketId) external nonReentrant whenNotPaused returns (uint256[] memory amounts_) {
        amounts_ = _claimBucketRewards(msg.sender, _bucketId, true);
    }

    /**
     * @notice batch claims all rewards distributed since token mint or last claim.
     *
     * @param _bucketIds The lock bucket ids whose rewards to claim
     *
     * @return amounts_ Claimed amountsof each reward token, for each bucketId
     */
    function batchClaimRewards(address _participant, uint256[] calldata _bucketIds)
        external
        nonReentrant
        whenNotPaused
        returns (uint256[][] memory amounts_)
    {
        amounts_ = new uint256[][](_bucketIds.length);
        for (uint256 i; i < _bucketIds.length; i++) {
            Participation memory position = participations[_participant][_bucketIds[i]];
            if (_participant != msg.sender || position.delegatee != msg.sender) revert NotAuthorized();
            amounts_[i] = _claimBucketRewards(_participant, _bucketIds[i], true);
        }
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
        if (_participant != msg.sender || position.delegatee != msg.sender) revert NotAuthorized();

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
        if (_limit == 0) revert NotValid();
        if (lastProcessedWeek == currentEpoch()) revert NotValid();

        uint256 week = lastProcessedWeek;
        uint256 goal = currentEpoch();

        if (goal - week > _limit) {
            goal = week + _limit;
        }
        uint256 pendingEpochs = goal - week;

        uint256 len = rewardTokens.length;
        while (week < goal) {
            WeekTotals storage prev = weekTotals[week];
            WeekTotals storage next = weekTotals[++week];

            next.netActiveVotes += prev.netActiveVotes;
            for (uint256 i; i < len; i++) {
                next.totalDistPerVote[i] += prev.totalDistPerVote[i];
            }
        }

        // Sync TWL Buckets
        _syncTWLBuckets(_limit);

        lastProcessedWeek = goal;

        emit AdvanceEpoch(goal, lastProcessedWeek);
    }

    /// @notice distributes a reward among all tokens, weighted by voting power
    /// @notice The reward gets allocated to all positions that have locked in
    /// @notice the current week. Fails, intentionally, if this number is zero.
    /// @notice Total rewards cannot exceed 2^128 tokens.
    /// @param _rewardTokenId index of the reward in `rewardTokens`
    /// @param _amount amount of reward token to distribute.
    function distributeReward(uint256 _rewardTokenId, uint256 _amount) external nonReentrant {
        if (lastProcessedWeek != currentEpoch()) revert AdvanceWeekFirst();
        if (_amount == 0) revert NotValid();
        if (_rewardTokenId == 0) revert NotValid(); // @dev rewardTokens[0] is 0x0

        WeekTotals storage totals = weekTotals[lastProcessedWeek];
        IERC20 rewardToken = rewardTokens[_rewardTokenId];
        // If this is a DBZ then there are no positions to give the reward to.
        // Since reward eligibility starts in the week after locking, there is
        // no way to give out rewards THIS week.
        // Cast is safe: `netActiveVotes` is at most zero by construction of
        // weekly totals and the requirement that they are up to date.
        totals.totalDistPerVote[_rewardTokenId] += (_amount * DIST_PRECISION) / uint256(totals.netActiveVotes);

        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit DistributeReward(address(rewardToken), msg.sender, _amount, _rewardTokenId);
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
     * @notice Set the maximum number of reward tokens.
     * @param _length The new maximum number of reward tokens.
     */
    function setMaxRewardTokensLength(uint256 _length) external onlyOwner {
        emit LogMaxRewardsLength(maxRewardTokens, _length, rewardTokens.length);
        maxRewardTokens = _length;
    }

    /**
     * @notice Add a reward token to the list of reward tokens.
     * @param _token The address of the reward token.
     */
    function addRewardToken(IERC20 _token) external onlyOwner returns (uint256) {
        if (rewardTokenIndex[_token] != 0) revert Registered();
        if (rewardTokens.length + 1 > maxRewardTokens) {
            revert TokenLimitReached();
        }
        rewardTokens.push(_token);

        uint256 newTokenIndex = rewardTokens.length - 1;
        rewardTokenIndex[_token] = newTokenIndex;

        emit AddRewardToken(address(_token), newTokenIndex);

        return newTokenIndex;
    }

    /**
     * @notice updates the Cluster address.
     * @dev can only be called by the owner.
     * @param _cluster the new address.
     */
    function setCluster(ICluster _cluster) external onlyOwner {
        if (address(_cluster) == address(0)) revert NotValid();
        cluster = _cluster;
        emit SetCluster(address(_cluster));
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
    function emergencySweep() external onlyOwner {
        if (lastEmergencySweep == 0 || block.timestamp < lastEmergencySweep + emergencySweepCooldown) {
            revert EmergencySweepCooldownNotReached();
        }

        // 1. Transfer the locks
        tapOFT.transfer(owner(), tapOFT.balanceOf(address(this)));

        // 2. Transfer the rewards
        uint256 len = rewardTokens.length;
        // Index starts at 1, see constructor
        for (uint256 i = 1; i < len; ++i) {
            IERC20 token = rewardTokens[i];
            if (token != IERC20(address(0x0))) {
                token.safeTransfer(owner(), token.balanceOf(address(this)));
            }
        }

        lastEmergencySweep = 0;
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

    /**
     * @dev Claim rewards on a token.
     * @param _account The account of the participant.
     * @param _bucketId The bucketId of the twTAP position.
     * @param transferRewards Whether to transfer the rewards to the account.
     * @return amounts_ Claimed amount of each reward token.
     */
    function _claimBucketRewards(address _account, uint256 _bucketId, bool transferRewards)
        internal
        returns (uint256[] memory amounts_)
    {
        amounts_ = claimable(_account, _bucketId);
        Participation storage position = participations[_account][_bucketId];
        position.lastInactive = uint40(currentEpoch());

        uint256 len = amounts_.length;
        for (uint256 i; i < len; ++i) {
            uint256 amount = amounts_[i];
            if (amount == 0) continue;
            if (transferRewards) {
                rewards[_account][_bucketId][i].claimed += amount;
                rewards[_account][_bucketId][i].pending = 0;
                rewardTokens[i].safeTransfer(_account, amount);
                emit ClaimReward(address(rewardTokens[i]), _account, _bucketId, amount, i);
            } else {
                rewards[_account][_bucketId][i].pending += amount;
            }
        }
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
        if (lastProcessedWeek != currentEpoch()) advanceWeek(currentEpoch() - lastProcessedWeek);

        if (_transferFrom) {
            bool isErr = pearlmit.transferFromERC20(msg.sender, address(this), address(tapOFT), _amount);
            if (isErr) revert NotAuthorized();
        }

        Participation storage position = participations[_participant][_bucketId];
        Bucket memory bucket = buckets[_bucketId];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);
        uint40 w0 = uint40(currentEpoch());
        uint40 w1 = uint40(_timestampToEpoch(expiry));

        if (position.expiry > 0 && block.timestamp < position.expiry) {
            // Clear the expected votes at the past expected expiration date
            weekTotals[_timestampToEpoch(position.expiry) + 1].netActiveVotes -=
                int256(uint256(position.tapAmount) * position.multiplier);
        }

        if (position.tapAmount > 0 && position.tapReleased == false) {
            _claimBucketRewards(_participant, _bucketId, false);
        }
        position.bucketId = _bucketId;
        position.tapReleased = false;
        position.lockedAt = uint56(block.timestamp);
        position.expiry = uint56(expiry);
        position.tapAmount = position.tapAmount + uint88(_amount);
        position.multiplier = bucket.rewardsMultiplier;
        position.lastInactive = w0;
        position.lastActive = w1;

        weekTotals[w0 + 1].netActiveVotes += int256(_amount * bucket.rewardsMultiplier);
        weekTotals[w1 + 1].netActiveVotes -= int256(uint256(position.tapAmount) * bucket.rewardsMultiplier);

        emit Participate(_participant, _bucketId, _amount, bucket.rewardsMultiplier, expiry, _bucketId);
    }
}
