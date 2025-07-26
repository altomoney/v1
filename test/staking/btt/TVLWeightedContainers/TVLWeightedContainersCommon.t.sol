// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TVLWeightedContainers} from "@alto/staking/TVLWeightedContainers.sol";
import {
    Container, MinMaxEpochs, ITVLWeightedContainersErrors
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

/// @notice Concrete implementation of TVLWeightedContainers for testing
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
}

contract TVLWeightedContainersCommon is Test {
    MockTVLWeightedContainers public containers;

    // Test constants
    uint256 public constant EPOCH_DURATION = 1 weeks;
    address public constant USER = address(0x1);
    address public constant OWNER = address(0x2);

    // Default container parameters
    Container public defaultContainer;

    function setUp() public virtual {
        vm.warp(1000000); // Set a reasonable starting timestamp

        // Set up default container
        defaultContainer = Container({
            growthRate: MinMaxEpochs({min: 1, max: 5}),
            decayRate: MinMaxEpochs({min: 1, max: 3}),
            duration: MinMaxEpochs({min: 10, max: 100}),
            isActive: false,
            maxRateDifferenceEpochs: 50,
            currentDurationEpochs: 0
        });
    }

    function _createContainerWithCustomParams(
        uint24 growthMin,
        uint24 growthMax,
        uint24 decayMin,
        uint24 decayMax,
        uint24 durationMin,
        uint24 durationMax,
        uint24 maxRateDifference
    ) internal pure returns (Container memory) {
        return Container({
            growthRate: MinMaxEpochs({min: growthMin, max: growthMax}),
            decayRate: MinMaxEpochs({min: decayMin, max: decayMax}),
            duration: MinMaxEpochs({min: durationMin, max: durationMax}),
            isActive: false,
            maxRateDifferenceEpochs: maxRateDifference,
            currentDurationEpochs: 0
        });
    }

    function _deployWithContainers(Container[] memory initialContainers) internal {
        containers = new MockTVLWeightedContainers(EPOCH_DURATION, initialContainers);
    }

    function _deployWithoutContainers() internal {
        Container[] memory emptyContainers = new Container[](0);
        containers = new MockTVLWeightedContainers(EPOCH_DURATION, emptyContainers);
    }

    function _deployWithSingleContainer() internal {
        Container[] memory singleContainer = new Container[](1);
        singleContainer[0] = defaultContainer;
        containers = new MockTVLWeightedContainers(EPOCH_DURATION, singleContainer);
    }
}
