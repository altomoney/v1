/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {TVLWeightedContainers} from "@alto/staking/TVLWeightedContainers.sol";
import {Container} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract MockTVLWeightedContainers is TVLWeightedContainers {
    constructor(uint256 epochDuration, Container[] memory initialContainers)
        TVLWeightedContainers(epochDuration, initialContainers)
    {}

    function startEpoch() external override {
        _startEpoch();
    }

    function addContainer(Container memory container) external returns (uint256) {
        return _addContainer(container);
    }

    function activateContainer(uint256 containerId) external {
        _activateContainer(containerId);
    }

    function deactivateContainer(uint256 containerId) external {
        _deactivateContainer(containerId);
    }

    function updateContainer(uint256 containerId, Container memory container) external returns (uint256) {
        return _updateContainer(containerId, container);
    }

    function updateContainerTVL(uint256 containerId, uint256 amount, uint256 fromEpoch, uint256 toEpoch, bool add)
        external
    {
        _updateContainerTVL(containerId, amount, fromEpoch, toEpoch, add);
    }

    function advanceEpoch(uint256 maxEpochsToProcess) external {
        _advanceEpoch(maxEpochsToProcess);
    }

    function processEpoch(uint256 epochToProcess) external {
        _processEpoch(epochToProcess);
    }

    function isContainerActive(uint256 containerId) external view returns (bool) {
        return _isContainerActive(containerId);
    }

    function getActiveContainerIds() external view returns (uint256[] memory) {
        return activeContainerIds;
    }

    function timestampToEpoch(uint256 timestamp) external view returns (uint256) {
        return _timestampToEpoch(timestamp);
    }

    function getContainer(uint256 containerId) external view returns (Container memory) {
        return containerById[containerId];
    }

    function getContainerAfterEpochProcessing(uint256 containerId, uint256 epochIdToProcess)
        external
        view
        returns (Container memory, uint24)
    {
        return _getContainerAfterEpochProcessing(containerId, epochIdToProcess);
    }

    function getTotalTvlForEpoch(uint256 epoch) external view returns (uint256) {
        return _getTotalTvlForEpoch(epoch);
    }

    function setContainerLockDuration(uint256 containerId, uint24 lockDuration) external {
        containerById[containerId].currentDurationEpochs = lockDuration;
    }

    function setLastProcessedEpoch(uint256 epoch) external {
        nextEpochToProcess = epoch;
    }
}
