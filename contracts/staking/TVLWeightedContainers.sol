// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {
    ITVLWeightedContainersStaticTypes,
    ITVLWeightedContainersBase,
    Container
} from "./interfaces/ITVLWeightedContainers.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title TVL Weighted Containers
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice An abstract contract for managing TVL weighted containers used for staking.
abstract contract TVLWeightedContainers is ITVLWeightedContainersStaticTypes {
    using FixedPointMath for uint256;

    /// @inheritdoc ITVLWeightedContainersBase
    uint256 public constant MAX_ACTIVE_CONTAINERS = 16;

    /// @inheritdoc ITVLWeightedContainersBase
    uint256 public immutable EPOCH_DURATION;

    /// @inheritdoc ITVLWeightedContainersBase
    uint256 public initializedAtTimestamp;

    /// @inheritdoc ITVLWeightedContainersBase
    uint256 public nextEpochToProcess;

    /// @inheritdoc ITVLWeightedContainersBase
    uint256 public totalContainerCount;

    /// @inheritdoc ITVLWeightedContainersBase
    uint256[] public activeContainerIds;

    /// @inheritdoc ITVLWeightedContainersStaticTypes
    mapping(uint256 => Container) public containerById;

    /// @inheritdoc ITVLWeightedContainersBase
    mapping(uint256 => mapping(uint256 => uint256)) public epochTVL;

    /// @dev Modifier to check if the epochs were started
    modifier whenEpochStarted() {
        if (initializedAtTimestamp == 0) {
            revert TVLWeightedContainersNotStarted();
        }
        _;
    }

    constructor(uint256 epochDuration, Container[] memory initialContainers) {
        if (epochDuration == 0) {
            revert TVLWeightedContainersInvalidInput();
        }
        EPOCH_DURATION = epochDuration;
        emit EpochDurationSet(epochDuration);

        for (uint256 i; i < initialContainers.length; i++) {
            _addContainer(initialContainers[i]);
        }
    }

    /// @inheritdoc ITVLWeightedContainersBase
    function currentEpoch() public view returns (uint256) {
        return _timestampToEpoch(block.timestamp);
    }

    /// @inheritdoc ITVLWeightedContainersBase
    function startEpoch() external virtual;

    /// @dev Initializes the epoch system - one-time initialization function
    /// @dev This gives the ability to start the epoch system anytime after the initial deployment
    function _startEpoch() internal {
        if (initializedAtTimestamp != 0) {
            revert TVLWeightedContainersAlreadyStarted();
        }

        if (activeContainerIds.length == 0) {
            revert TVLWeightedContainersNoContainers();
        }

        initializedAtTimestamp = block.timestamp;

        emit EpochStarted(initializedAtTimestamp);
    }

    /// @dev Updates the TVL of a container for a specific epoch
    /// @param containerId The id of the container to update the TVL of
    /// @param amount The amount of TVL to update
    /// @param fromEpoch The epoch to start updating the TVL from
    /// @param toEpoch The epoch to stop updating the TVL at
    /// @param add Whether to add or subtract the amount from the TVL
    function _updateContainerTVL(uint256 containerId, uint256 amount, uint256 fromEpoch, uint256 toEpoch, bool add)
        internal
        whenEpochStarted
    {
        if (nextEpochToProcess != currentEpoch()) {
            revert TVLWeightedContainersCurrentEpochAlreadyFinished();
        }

        if (add && fromEpoch != nextEpochToProcess) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (fromEpoch > toEpoch) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (fromEpoch < nextEpochToProcess) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (!_isContainerActive(containerId)) {
            revert TVLWeightedContainersInvalidInput();
        }

        for (uint256 epoch = fromEpoch; epoch < toEpoch; epoch++) {
            if (add) {
                epochTVL[epoch][containerId] += amount;
            } else {
                // Protect against underflow (this should never happen)
                if (epochTVL[epoch][containerId] < amount) {
                    revert TVLWeightedContainersInvalidInput();
                }
                epochTVL[epoch][containerId] -= amount;
            }
        }

        emit ContainerTVLUpdated(fromEpoch, containerId, amount, add);
    }

    /// @dev Process the epoch for all active containers
    /// @param epochToProcess The epoch to process
    /// @dev This function is used to process the epoch for all active containers
    /// @dev This function is used to update the duration of the containers based on the TVL share
    /// @dev This function is used to process the containers according to the growth and decay rules
    function _processEpoch(uint256 epochToProcess) internal whenEpochStarted {
        uint256 totalTvl = _getTotalTvlForEpoch(epochToProcess);

        for (uint256 cId; cId < activeContainerIds.length; cId++) {
            _processContainer(epochToProcess, activeContainerIds[cId], totalTvl);
        }
    }

    /// @dev Process the container for a specific epoch
    /// @param epochToProcess The epoch to process
    /// @param containerId The id of the container to process
    /// @param totalTvl The total TVL of all active containers
    /// @dev Used in the `_processEpoch` function
    /// @dev This function is used to process the container for a specific epoch
    /// @dev This function is used to update the duration of the container based on the TVL share
    function _processContainer(uint256 epochToProcess, uint256 containerId, uint256 totalTvl)
        internal
        whenEpochStarted
    {
        Container storage container = containerById[containerId];

        uint24 currentDurationEpochsBefore = container.currentDurationEpochs;

        container.currentDurationEpochs = _getNextDurationEpochsForContainer(epochToProcess, containerId, totalTvl);

        emit ContainerDurationUpdated(containerId, currentDurationEpochsBefore, container.currentDurationEpochs);
    }

    /// @dev Applies TVL growth and decay rules to the container's currentDurationEpochs without writing the results
    /// @param epochToProcess The epoch to process
    /// @param containerId The id of the container to process
    /// @param totalTvl The total TVL of all active containers
    /// @dev Used in the `_processContainer` function as well as `_getContainerInEpoch`
    /// @dev This function is used to process the container for a specific epoch without writing the results
    /// @dev This function is used to get the duration of the container based on the TVL share
    function _getNextDurationEpochsForContainer(uint256 epochToProcess, uint256 containerId, uint256 totalTvl)
        internal
        view
        returns (uint24)
    {
        Container storage container = containerById[containerId];

        uint24 currentDurationEpochsNext = container.currentDurationEpochs;

        uint256 containerTvlSharePercentage =
            totalTvl > 0 ? epochTVL[epochToProcess][containerId].divideWithPrecisionDown(totalTvl) : 0;

        uint256 newRequestedDurationEpochs =
            (containerTvlSharePercentage > 0
                        ? uint256(container.duration.max - container.duration.min)
                            .divideWithRoundingHalfUp(containerTvlSharePercentage, MATH_PRECISION)
                        : 0) + container.duration.min;

        if (newRequestedDurationEpochs > container.currentDurationEpochs) {
            uint256 epochsToGrow;

            uint256 difference = newRequestedDurationEpochs - container.currentDurationEpochs;
            uint256 differenceFromMaxRatePercentage =
                uint256(difference).divideWithPrecisionUp(container.maxRateDifferenceEpochs);

            if (differenceFromMaxRatePercentage < MATH_PRECISION) {
                epochsToGrow = uint256(container.growthRate.max - container.growthRate.min)
                    .divideWithRounding(differenceFromMaxRatePercentage, MATH_PRECISION, true)
                + container.growthRate.min;
            } else {
                epochsToGrow = container.growthRate.max;
            }

            if (epochsToGrow + container.currentDurationEpochs > container.duration.max) {
                currentDurationEpochsNext = container.duration.max;
            } else {
                currentDurationEpochsNext += uint24(epochsToGrow);
            }
        } else if (newRequestedDurationEpochs < container.currentDurationEpochs) {
            uint256 epochsToDecay;

            uint256 difference = container.currentDurationEpochs - newRequestedDurationEpochs;
            uint256 differenceFromMaxRatePercentage =
                uint256(difference).divideWithPrecisionDown(container.maxRateDifferenceEpochs);

            if (differenceFromMaxRatePercentage < MATH_PRECISION) {
                epochsToDecay = uint256(container.decayRate.max - container.decayRate.min)
                    .divideWithRounding(differenceFromMaxRatePercentage, MATH_PRECISION, false)
                + container.decayRate.min;
            } else {
                epochsToDecay = container.decayRate.max;
            }

            if (
                epochsToDecay > container.currentDurationEpochs
                    || container.currentDurationEpochs - epochsToDecay < container.duration.min
            ) {
                currentDurationEpochsNext = container.duration.min;
            } else {
                currentDurationEpochsNext -= uint24(epochsToDecay);
            }
        }

        return currentDurationEpochsNext;
    }

    /// @dev Returns container data and currentDurationEpochs after processinga specific epoch with current state of TVL
    /// @param containerId The id of the container to get
    /// @param epochIdToProcess The epoch to get the container's currentDurationEpochs after processing
    /// @return Container storage The container data
    /// @return uint24 currentDurationEpochsNext The current duration epochs next
    /// @dev This function is helper function for the 3rd party contract to get currently calculated currentDurationEpochs in coming epoch
    function _getContainerAfterEpochProcessing(uint256 containerId, uint256 epochIdToProcess)
        internal
        view
        returns (Container storage, uint24)
    {
        if (!_isContainerActive(containerId)) {
            return (containerById[containerId], containerById[containerId].currentDurationEpochs);
        }

        uint24 currentDurationEpochsNext =
            _getNextDurationEpochsForContainer(epochIdToProcess, containerId, _getTotalTvlForEpoch(epochIdToProcess));
        return (containerById[containerId], currentDurationEpochsNext);
    }

    /// @dev Returns the total TVL for a specific epoch
    /// @param epoch The epoch to get the total TVL for
    /// @return totalTvl The total TVL for the epoch
    function _getTotalTvlForEpoch(uint256 epoch) internal view returns (uint256 totalTvl) {
        for (uint256 cId; cId < activeContainerIds.length; cId++) {
            totalTvl += epochTVL[epoch][activeContainerIds[cId]];
        }
    }

    /// @dev Validates the container
    /// @param container The container to validate
    /// @dev This function is used to validate the container when adding or updating a container
    function _validateContainer(Container memory container) internal pure {
        if (
            container.growthRate.min > container.growthRate.max || container.growthRate.min == 0
                || container.growthRate.max == 0
        ) {
            revert TVLWeightedContainersInvalidInput();
        }
        if (
            container.decayRate.min > container.decayRate.max || container.decayRate.min == 0
                || container.decayRate.max == 0
        ) {
            revert TVLWeightedContainersInvalidInput();
        }
        if (
            container.duration.min > container.duration.max || container.duration.min == 0
                || container.duration.max == 0
        ) {
            revert TVLWeightedContainersInvalidInput();
        }
        if (container.maxRateDifferenceEpochs > container.duration.max || container.maxRateDifferenceEpochs == 0) {
            revert TVLWeightedContainersInvalidInput();
        }
        if (container.currentDurationEpochs != 0) {
            revert TVLWeightedContainersInvalidInput();
        }
        if (container.isActive) {
            revert TVLWeightedContainersInvalidInput();
        }
    }

    /// @dev Adds a new container to the system
    /// @param container The container to add
    /// @dev currentDurationEpochs has to be 0 and isActive has to be false all the other validation rules are
    /// described in the `_validateContainer` function
    /// @dev containerIds start from 1 and are incremented by 1 for each new container
    function _addContainer(Container memory container) internal returns (uint256 containerId) {
        _validateContainer(container);

        container.currentDurationEpochs = container.duration.min;

        // container IDs start from 1
        totalContainerCount++;

        containerById[totalContainerCount] = container;

        emit ContainerAdded(totalContainerCount, container);

        return totalContainerCount;
    }

    /// @dev Updates a container
    /// @param _containerId The id of the container to update
    /// @param container The container to update
    /// @dev Updating currentDurationEpochs is not allowed and same rules apply as for validation in the `_addContainer` function.
    /// On the top of that provided duration.min and duration.max have to be greater than the current currentDurationEpochs.
    function _updateContainer(uint256 _containerId, Container memory container) internal returns (uint256) {
        Container memory containerBefore = containerById[_containerId];

        if (!_isContainerExists(_containerId)) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (
            container.duration.min > containerBefore.currentDurationEpochs
                || container.duration.max < containerBefore.currentDurationEpochs
        ) {
            revert TVLWeightedContainersInvalidInput();
        }

        _validateContainer(container);

        container.currentDurationEpochs = containerBefore.currentDurationEpochs;
        container.isActive = containerBefore.isActive;

        emit ContainerUpdated(_containerId, containerBefore, container);

        containerById[_containerId] = container;

        return _containerId;
    }

    /// @dev Activates a container by adding it to the activeContainerIds array.
    /// @param containerId The id of the container to activate.
    /// @dev After actiation conainer is considered active and used in the `_processEpoch` function
    function _activateContainer(uint256 containerId) internal {
        if (activeContainerIds.length >= MAX_ACTIVE_CONTAINERS) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (!_isContainerExists(containerId)) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (_isContainerActive(containerId)) {
            revert TVLWeightedContainersInvalidInput();
        }

        containerById[containerId].isActive = true;

        activeContainerIds.push(containerId);

        emit ContainerActivated(containerId);
    }

    /// @dev Deactivates a container by removing it from the activeContainerIds array.
    /// @param containerId The id of the container to deactivate.
    /// @dev Once container is deactivated it is considered inactive and not used in the `_processEpoch` function.
    function _deactivateContainer(uint256 containerId) internal {
        // we can't deactivate container that is not active
        if (!_isContainerActive(containerId)) {
            revert TVLWeightedContainersInvalidInput();
        }

        // Note: Linear search is acceptable here as MAX_ACTIVE_CONTAINERS is capped at 16
        // swap and pop the last element
        for (uint256 i; i < activeContainerIds.length; i++) {
            if (activeContainerIds[i] == containerId) {
                activeContainerIds[i] = activeContainerIds[activeContainerIds.length - 1];
                activeContainerIds.pop();
                containerById[containerId].isActive = false;
                emit ContainerDeactivated(containerId);
                return;
            }
        }

        revert TVLWeightedContainersInvalidInput();
    }

    /// @dev Converts a timestamp to an epoch
    /// @param timestamp The timestamp to convert
    /// @return The epoch number
    function _timestampToEpoch(uint256 timestamp) internal view returns (uint256) {
        if (initializedAtTimestamp == 0) {
            revert TVLWeightedContainersNotStarted();
        }

        return (timestamp - initializedAtTimestamp) / EPOCH_DURATION;
    }

    /// @dev Advances the epoch
    /// @param _maxEpochsToProcess The maximum number of epochs to process
    /// @dev This function is used to advance specific number of epochs.
    function _advanceEpoch(uint256 _maxEpochsToProcess) internal whenEpochStarted {
        if (_maxEpochsToProcess == 0) {
            _maxEpochsToProcess = uint256(type(uint256).max);
        }

        uint256 targetEpoch = currentEpoch();

        if (nextEpochToProcess == targetEpoch) {
            revert TVLWeightedContainersCurrentEpochNotFinished();
        }

        uint256 epochsToProcess = targetEpoch - nextEpochToProcess;

        if (epochsToProcess > _maxEpochsToProcess) {
            epochsToProcess = _maxEpochsToProcess;
        }

        uint256 nextEpochToProcessBefore = nextEpochToProcess;

        for (uint256 i; i < epochsToProcess; i++) {
            _processEpoch(nextEpochToProcess);
            nextEpochToProcess++;
        }

        emit AdvanceEpoch(nextEpochToProcessBefore, nextEpochToProcess);
    }

    /// @dev Checks if a container is active.
    /// @param containerId The id of the container to check.
    function _isContainerActive(uint256 containerId) internal view returns (bool) {
        return containerById[containerId].isActive;
    }

    /// @dev Checks if a container exists. Container is considered to exist if duration.min is not 0
    /// as that's one of the constrains for valid container.
    /// @param containerId The id of the container to check.
    function _isContainerExists(uint256 containerId) internal view returns (bool) {
        return containerById[containerId].duration.min != 0;
    }
}
