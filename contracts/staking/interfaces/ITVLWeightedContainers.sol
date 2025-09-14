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

interface ITVLWeightedContainers is ITVLWeightedContainersErrors, ITVLWeightedContainersEvents {
    /// @notice Returns the TVL of a container at a specific epoch
    /// @param epoch The epoch number
    /// @param containerId The container ID
    /// @return The TVL of the container at the specific epoch
    function epochTVL(uint256 epoch, uint256 containerId) external view returns (uint256);

    /**
     * @notice Returns the current epoch number
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Returns the containers
     * @return The containers
     */
    function getContainer(uint256 containerId) external view returns (Container memory);

    function startEpoch() external;

    function EPOCH_DURATION() external view returns (uint256);

    function initializedAtTimestamp() external view returns (uint256);
}
