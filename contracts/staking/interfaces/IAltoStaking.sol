// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {
    ITVLWeightedContainers,
    ITVLWeightedContainersStaticTypes,
    Container,
    MinMaxEpochs
} from "./ITVLWeightedContainers.sol";

struct StakingPosition {
    uint256 lockedTimestamp; // timestamp when lock was created
    uint256 expiryTimestamp; // expiry timestamp.
    uint256 amountLocked; // amount of lock token locked
}

struct StakingContainer {
    /// @notice The multiplier is used to calculate the votes of a container.
    /// votes = multiplier * locked amount in all containers summed up
    uint256 multiplier;
    /// @notice Whether the container is deprecated.
    /// @dev If the container is deprecated, users are not able to lock new tokens into it.
    bool isDeprecated;
}

/// @notice This struct merges container structs into one
/// @dev This is a helper struct when fetching container data
struct StakingContainerExtended {
    /// Copy of Container struct
    MinMaxEpochs growthRate;
    MinMaxEpochs decayRate;
    MinMaxEpochs duration;
    bool isActive;
    uint24 maxRateDifferenceEpochs;
    uint24 currentDurationEpochs;
    /// Copy of StakingContainer struct
    uint256 multiplier;
    bool isDeprecated;
    /// The next duration epochs of the container
    uint24 currentDurationEpochsNext;
}

interface IAltoStakingErrors {
    error AltoStakingInvalidInput();
    error AltoStakingUnauthorized();
    error AltoStakingContainerDeprecated();
    error AltoStakingNoPosition();
    error AltoStakingTryingToLockForTooManyEpochs();
    error AltoStakingPositionNotExpired();
    error AltoStakingNotPausedForEmergencySweep();
}

interface IAltoStakingEvents {
    event LockPosition(
        address indexed caller,
        address indexed onBehalf,
        uint256 containerId,
        uint256 amount,
        uint256 expiryTimestamp,
        bool isReuse
    );

    event UnlockPosition(
        address indexed caller, address indexed onBehalf, address indexed receiver, uint256 containerId, uint256 amount
    );

    event EmergencySweep(address indexed caller, address indexed receiver, uint256 amount);

    event ContainerDeprecate(uint256 indexed containerId);

    event ContainerMultiplierUpdated(uint256 indexed containerId, uint256 multiplier);

    event MaxMultiplierStakingContainerIdUpdated(uint256 indexed containerId, uint256 multiplier);
}

interface IAltoStakingBase is IAltoStakingErrors, IAltoStakingEvents, IAuth, IPausable {
    /// @notice The address of the lock token.
    /// @dev This token is trusted and does not need any reentrancy protection.
    function LOCK_TOKEN() external view returns (address);

    /// @notice The id of the container with the highest multiplier.
    /// @dev This is used for locking in the max multiplier container during AltoRewardsDistributor.claimRewardTokens.
    function maxMultiplierStakingContainerId() external view returns (uint256);

    /// @notice Get the votes of an account at current time.
    /// @param account The account of the lock position owner.
    /// @return votes The votes of the account.
    /// @dev Votes are calculated based on the amount of lock tokens locked in all active containers
    /// (including deprecated containers) multiplied by the multiplier of the container.
    /// @dev This is intended to be used only for voting purposes and never in write functions
    /// (otherwise it could lead to a gas bomb).
    function getVotes(address account) external view returns (uint256);

    /// @notice Lock tokens into a container.
    /// @param onBehalf The address of the user who will become the owner of the lock position.
    /// @param amount The amount of lock tokens to lock.
    /// @param containerId The id of the container to lock the tokens into.
    /// @param isReuse Whether to reuse expired or non-expired position. Setting this to true will not create a new position,
    /// but will update the existing position's expiry timestamp if it exists.
    /// @param maxEpochsToLockFor The maximum number of epochs to lock for. Useful when max epochs are updated
    /// during UI interaction and UI shows an old number of epochs to lock for.
    /// @return amount The amount of lock tokens locked.
    function lock(address onBehalf, uint256 amount, uint256 containerId, bool isReuse, uint256 maxEpochsToLockFor)
        external
        returns (uint256);

    /// @notice Unlocks all tokens from a container and sends them to the receiver.
    /// @param onBehalf The address of the user who is the owner of the stake position.
    /// @param receiver The address to send the lock tokens to.
    /// @param containerId The id of the container to unlock the tokens from.
    /// @return amount The amount of lock tokens released.
    /// @dev Positions in deprecated and/or deactivated containers can be unlocked once expired.
    function unlock(address onBehalf, address receiver, uint256 containerId) external returns (uint256);

    /// @notice Get the stake position of an account in a container.
    /// @param account The account of the lock position owner.
    /// @param containerId The containerId of the stake position.
    /// @return position The StakePosition of the account in the container.
    function getPosition(address account, uint256 containerId) external view returns (StakingPosition memory position);

    /// @notice Get the container after processing a specific epoch.
    /// @param containerId The id of the container to get the container of.
    /// @param epochIdToProcess The epoch to get the container after processing.
    /// @return stakingContainerExtended The extended staking container of the container.
    function getContainerAfterProcessing(uint256 containerId, uint256 epochIdToProcess)
        external
        view
        returns (StakingContainerExtended memory stakingContainerExtended);

    /// @notice Advance the epoch.
    /// @param limit The maximum number of epochs to process in one call.
    function advanceEpoch(uint256 limit) external;

    /// @notice Emergency sweep of all lock tokens in case of a critical issue.
    /// @dev This function can only be called if the contract is paused. Contract should
    /// not be used afterwards (only in some rare cases - i.e. calling sweep and re-adding
    /// same amount of funds in the same epoch).
    function emergencySweep() external;

    /// @notice Add a new container.
    /// @param container The container to add.
    /// @param multiplier The multiplier of the container.
    function addContainer(Container memory container, uint256 multiplier) external;

    /// @notice Update a container.
    /// @param containerId The id of the container to update.
    /// @param container The container to update.
    /// @param multiplier The multiplier of the container.
    function updateContainer(uint256 containerId, Container memory container, uint256 multiplier) external;

    /// @notice Activate a container.
    /// @param containerId The id of the container to activate.
    function activateContainer(uint256 containerId) external;

    /// @notice Deactivate a container.
    /// @param containerId The id of the container to deactivate.
    function deactivateContainer(uint256 containerId) external;

    /// @notice Deprecate a container.
    /// @param containerId The id of the container to deprecate.
    /// @dev Deprecated containers can't be used to lock new tokens.
    /// @dev Deprecated containers are not able to be activated again.
    /// @dev Deprecated containers can't be adjusted.
    function deprecateContainer(uint256 containerId) external;
}

interface IAltoStaking is ITVLWeightedContainers, IAltoStakingBase {
    /// @notice The staking position of an account in a container.
    /// @param account The account of the lock position owner.
    /// @param containerId The containerId of the stake position.
    /// @return position The StakePosition of the account in the container.
    function positions(address account, uint256 containerId) external view returns (StakingPosition memory);

    /// @notice The staking container by id.
    /// @param containerId The id of the container to get the staking container of.
    /// @return stakingContainer The staking container of the container.
    function stakingContainerById(uint256 containerId) external view returns (StakingContainer memory);
}

interface IAltoStakingStaticTypes is ITVLWeightedContainersStaticTypes, IAltoStakingBase {
    /// @notice The staking position of an account in a container.
    /// @param account The account of the lock position owner.
    /// @param containerId The containerId of the stake position.
    /// @return lockedTimestamp The timestamp when the lock was created.
    /// @return expiryTimestamp The expiry timestamp.
    /// @return amountLocked The amount of lock tokens locked.
    function positions(address account, uint256 containerId)
        external
        view
        returns (uint256 lockedTimestamp, uint256 expiryTimestamp, uint256 amountLocked);

    /// @notice The staking container by id.
    /// @param containerId The id of the container to get the staking container of.
    /// @return multiplier The multiplier of the container.
    /// @return isDeprecated Whether the container is deprecated.
    function stakingContainerById(uint256 containerId) external view returns (uint256 multiplier, bool isDeprecated);
}
