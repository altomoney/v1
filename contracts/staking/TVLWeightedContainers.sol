// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ITVLWeightedContainers, Container} from "./interfaces/ITVLWeightedContainers.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract TVLWeightedContainers is ITVLWeightedContainers {
    using FixedPointMath for uint256;

    uint256 public constant MAX_ACTIVE_CONTAINERS = 16;

    uint256 public immutable EPOCH_DURATION;
    uint256 public initializedAtTimestamp;
    uint256 public nextEpochToProcess;
    uint256 public totalContainerCount;

    mapping(uint256 => Container) public containerById;
    uint256[] public activeContainerIds;

    /// @inheritdoc ITVLWeightedContainers
    mapping(uint256 => mapping(uint256 => uint256)) public epochTVL;

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

        for (uint256 i = 0; i < initialContainers.length; i++) {
            _addContainer(initialContainers[i]);
        }
    }

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

        if (!containerById[containerId].isActive) {
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

    /**
     * @dev Update enabled containers based on the total deposits in the contract.
     */
    function _processEpoch(uint256 epochToProcess) internal whenEpochStarted {
        uint256 totalTvl = 0;

        for (uint256 cId; cId < activeContainerIds.length; cId++) {
            totalTvl += epochTVL[epochToProcess][activeContainerIds[cId]];
        }

        for (uint256 cId; cId < activeContainerIds.length; cId++) {
            _processContainer(epochToProcess, activeContainerIds[cId], totalTvl);
        }
    }

    function _processContainer(uint256 epochToProcess, uint256 containerId, uint256 totalTvl)
        internal
        whenEpochStarted
    {
        Container storage container = containerById[containerId];

        uint24 currentDurationEpochsBefore = container.currentDurationEpochs;

        uint256 containerTvlSharePercentage =
            totalTvl > 0 ? epochTVL[epochToProcess][containerId].divideWithPrecisionDown(totalTvl) : 0;

        uint256 newRequestedDurationEpochs = (
            containerTvlSharePercentage > 0
                ? uint256(container.duration.max - container.duration.min).divideWithRoundingHalfUp(
                    containerTvlSharePercentage, MATH_PRECISION
                )
                : 0
        ) + container.duration.min;

        if (newRequestedDurationEpochs > container.currentDurationEpochs) {
            uint256 epochsToGrow;

            uint256 difference = newRequestedDurationEpochs - container.currentDurationEpochs;
            uint256 differenceFromMaxRatePercentage =
                uint256(difference).divideWithPrecisionUp(container.maxRateDifferenceEpochs);

            if (differenceFromMaxRatePercentage < MATH_PRECISION) {
                epochsToGrow = uint256(container.growthRate.max - container.growthRate.min).divideWithRounding(
                    differenceFromMaxRatePercentage, MATH_PRECISION, true
                ) + container.growthRate.min;
            } else {
                epochsToGrow = container.growthRate.max;
            }

            if (epochsToGrow + container.currentDurationEpochs > container.duration.max) {
                container.currentDurationEpochs = container.duration.max;
            } else {
                container.currentDurationEpochs += uint24(epochsToGrow);
            }
        } else if (newRequestedDurationEpochs < container.currentDurationEpochs) {
            uint256 epochsToDecay;

            uint256 difference = container.currentDurationEpochs - newRequestedDurationEpochs;
            uint256 differenceFromMaxRatePercentage =
                uint256(difference).divideWithPrecisionDown(container.maxRateDifferenceEpochs);

            if (differenceFromMaxRatePercentage < MATH_PRECISION) {
                epochsToDecay = uint256(container.decayRate.max - container.decayRate.min).divideWithRounding(
                    differenceFromMaxRatePercentage, MATH_PRECISION, false
                ) + container.decayRate.min;
            } else {
                epochsToDecay = container.decayRate.max;
            }

            if (container.currentDurationEpochs - epochsToDecay < container.duration.min) {
                container.currentDurationEpochs = container.duration.min;
            } else {
                container.currentDurationEpochs -= uint24(epochsToDecay);
            }
        }

        emit ContainerDurationUpdated(containerId, currentDurationEpochsBefore, container.currentDurationEpochs);
    }

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

    function _addContainer(Container memory container) internal returns (uint256 containerId) {
        _validateContainer(container);

        container.currentDurationEpochs = container.duration.min;

        // container IDs start from 1
        totalContainerCount++;

        containerById[totalContainerCount] = container;

        emit ContainerAdded(totalContainerCount, container);

        return totalContainerCount;
    }

    /// @dev Activates a container by adding it to the activeContainerIds array.
    /// @param containerId The id of the container to activate.
    function _activateContainer(uint256 containerId) internal {
        if (activeContainerIds.length >= MAX_ACTIVE_CONTAINERS) {
            revert TVLWeightedContainersInvalidInput();
        }

        if (containerById[containerId].isActive) {
            revert TVLWeightedContainersInvalidInput();
        }

        containerById[containerId].isActive = true;

        activeContainerIds.push(containerId);

        emit ContainerActivated(containerId);
    }

    /// @dev Deactivates a container by removing it from the activeContainerIds array.
    /// If container is not active, does nothing.
    /// @param containerId The id of the container to deactivate.
    function _deactivateContainer(uint256 containerId) internal {
        if (!containerById[containerId].isActive) {
            revert TVLWeightedContainersInvalidInput();
        }

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

    /**
     * @dev Updates container params at a specific index.
     * @param _containerId Index of the container to update
     * @param container Container to add into the system, ignores currentDurationEpochs field
     */
    function _updateContainer(uint256 _containerId, Container memory container) internal returns (uint256) {
        Container memory containerBefore = containerById[_containerId];

        if (
            _isContainerActive(_containerId)
                && (
                    container.duration.min > containerBefore.currentDurationEpochs
                        || container.duration.max < containerBefore.currentDurationEpochs
                )
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

    /**
     * @notice Returns the current epoch number
     */
    function currentEpoch() public view returns (uint256) {
        return _timestampToEpoch(block.timestamp);
    }

    function _timestampToEpoch(uint256 timestamp) internal view returns (uint256) {
        return (timestamp - initializedAtTimestamp) / EPOCH_DURATION;
    }

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

    /// @inheritdoc ITVLWeightedContainers
    function startEpoch() external virtual;

    /// @inheritdoc ITVLWeightedContainers
    function getContainer(uint256 containerId) external view returns (Container memory) {
        return containerById[containerId];
    }

    function _isContainerActive(uint256 containerId) internal view returns (bool) {
        for (uint256 i; i < activeContainerIds.length; i++) {
            if (activeContainerIds[i] == containerId) {
                return true;
            }
        }
        return false;
    }
}
