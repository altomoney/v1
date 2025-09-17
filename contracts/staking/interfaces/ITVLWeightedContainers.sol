// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

struct MinMaxEpochs {
    uint24 min;
    uint24 max;
}

/// @notice Container is a struct that contains the parameters of a single TVL container
struct Container {
    /// @notice The growth rate of the container, the min and max number of epochs to
    /// grow the duration when the TVL share is higher than in the last epoch
    MinMaxEpochs growthRate;
    /// @notice The decay rate of the container, the min and max number of epochs to
    /// decay the duration when the TVL share is lower than in the last epoch
    MinMaxEpochs decayRate;
    /// @notice The duration of the container, the min and max number of epochs that the container can have
    MinMaxEpochs duration;
    /// @notice Whether the container is active, if container is inactive:
    bool isActive;
    /// @notice The maximum number of epochs' difference to reach maximum growth or decay rate
    uint24 maxRateDifferenceEpochs;
    /// @notice The current duration epochs of the container
    uint24 currentDurationEpochs;
}

interface ITVLWeightedContainersErrors {
    error TVLWeightedContainersInvalidInput();
    error TVLWeightedContainersCurrentEpochNotFinished();
    error TVLWeightedContainersContainerDisabled();
    error TVLWeightedContainersCurrentEpochAlreadyFinished();
    error TVLWeightedContainersNotStarted();
    error TVLWeightedContainersAlreadyStarted();
    error TVLWeightedContainersNoContainers();
}

interface ITVLWeightedContainersEvents {
    event EpochDurationSet(uint256 epochDuration);
    event EpochStarted(uint256 initializedAtTimestamp);
    event ContainerTVLUpdated(uint256 indexed epoch, uint256 indexed containerId, uint256 deltaAmount, bool add);
    event ContainerAdded(uint256 indexed containerId, Container container);
    event ContainerUpdated(uint256 indexed index, Container containerBefore, Container containerAfter);
    event ContainerActivated(uint256 indexed containerId);
    event ContainerDeactivated(uint256 indexed containerId);
    event AdvanceEpoch(uint256 indexed oldEpoch, uint256 indexed newEpoch);
    event ContainerDurationUpdated(uint256 indexed containerId, uint24 oldDuration, uint24 newDuration);
}

interface ITVLWeightedContainersBase is ITVLWeightedContainersErrors, ITVLWeightedContainersEvents {
    /// @notice The maximum number of active containers
    /// @dev This is used to limit the number of containers that can be active at the same time
    /// to avoid potential gas bomb
    function MAX_ACTIVE_CONTAINERS() external view returns (uint256);

    /// @notice Epoch duration in seconds of one update cycle
    /// @dev TVL weighted containers update their TVL after each epoch expires
    function EPOCH_DURATION() external view returns (uint256);

    /// @notice Timestamp when the first epoch started
    /// @dev This is used to calculate the current epoch number
    function initializedAtTimestamp() external view returns (uint256);

    /// @notice The next epoch to process TVL weighted containers in
    /// @dev Increased by 1 after each epoch is processed
    function nextEpochToProcess() external view returns (uint256);

    /// @notice Current number of all containers regardless of their status
    /// @dev This holds current highest container id and is used to determine the next container id
    /// @dev This is to keep the track of how many containers are in the `containerById`
    function totalContainerCount() external view returns (uint256);

    /// @notice Returns the active container ids
    /// @dev This is to keep the track of which containers are active
    /// @dev This is used to process the containers in the `_processEpoch` function
    function activeContainerIds(uint256 index) external view returns (uint256);

    /// @notice Returns the TVL of a container at a specific epoch
    /// @param epoch The epoch number
    /// @param containerId The container ID
    /// @return The TVL of the container at the specific epoch
    function epochTVL(uint256 epoch, uint256 containerId) external view returns (uint256);

    /// @notice Returns the current epoch number based on current block timestamp and initializedAtTimestamp
    function currentEpoch() external view returns (uint256);

    /// @notice Public function to initialize the epoch system
    function startEpoch() external;
}

interface ITVLWeightedContainers is ITVLWeightedContainersBase {
    /// @notice Returns the container by id
    /// @dev This is to get the container by id
    /// @param containerId The id of the container to get
    /// @return The Container struct with the container details
    function containerById(uint256 containerId) external view returns (Container memory);
}

interface ITVLWeightedContainersStaticTypes is ITVLWeightedContainersBase {
    /// @notice Returns the container by id
    /// @dev This is to get the container by id
    /// @param containerId The id of the container to get
    /// @return growthRate The growth rate of the container
    /// @return decayRate The decay rate of the container
    /// @return duration The duration of the container
    /// @return isActive Whether the container is active
    /// @return maxRateDifferenceEpochs The maximum rate difference epochs
    /// @return currentDurationEpochs The current duration epochs
    function containerById(uint256 containerId)
        external
        view
        returns (
            MinMaxEpochs memory growthRate,
            MinMaxEpochs memory decayRate,
            MinMaxEpochs memory duration,
            bool isActive,
            uint24 maxRateDifferenceEpochs,
            uint24 currentDurationEpochs
        );
}
