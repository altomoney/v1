// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TVLWeightedContainers} from "@alto/staking/TVLWeightedContainers.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract TVLWeightedContainersMock is TVLWeightedContainers {
    constructor(uint256 epochDuration, Container[] memory initialContainers)
        TVLWeightedContainers(epochDuration, initialContainers)
    {}

    function startEpoch() external override {
        _startEpoch();
    }

    function updateContainerTVL(uint8 containerId, uint256 amount, uint256 fromEpoch, uint256 toEpoch, bool isAdd)
        external
    {
        _updateContainerTVL(containerId, amount, fromEpoch, toEpoch, isAdd);
    }

    function advanceEpoch(uint256 maxEpochsToProcess) external {
        _advanceEpoch(maxEpochsToProcess);
    }

    function addContainer(Container memory container) external {
        _addContainer(container);
    }

    function updateContainer(uint256 containerId, Container memory container) external {
        _updateContainer(containerId, container);
    }

    function setContainerLockDuration(uint256 containerId, uint24 lockDuration) external {
        containerById[containerId].currentDurationEpochs = lockDuration;
    }

    function setLastProcessedEpoch(uint256 epoch) external {
        nextEpochToProcess = epoch;
    }

    function activateContainer(uint256 containerId) external {
        _activateContainer(containerId);
    }

    function deactivateContainer(uint256 containerId) external {
        _deactivateContainer(containerId);
    }
}

contract TVLWeightedContainers_Main is Test {
    function setUp() public {}

    function test_Main() public {
        Container[] memory initialContainers = new Container[](3);

        initialContainers[0] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 3}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 1, max: 8}),
            maxRateDifferenceEpochs: 4,
            currentDurationEpochs: 0,
            isActive: false
        });

        initialContainers[1] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 3}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 2, max: 12}),
            maxRateDifferenceEpochs: 10,
            currentDurationEpochs: 0,
            isActive: false
        });

        initialContainers[2] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 3}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 3, max: 16}),
            maxRateDifferenceEpochs: 4,
            currentDurationEpochs: 0,
            isActive: false
        });

        TVLWeightedContainersMock tVLWeightedContainers = new TVLWeightedContainersMock(1 days, initialContainers);

        tVLWeightedContainers.activateContainer(1);
        tVLWeightedContainers.activateContainer(2);
        tVLWeightedContainers.activateContainer(3);

        tVLWeightedContainers.setContainerLockDuration(1, 2);
        tVLWeightedContainers.setContainerLockDuration(2, 5);
        tVLWeightedContainers.setContainerLockDuration(3, 10);

        tVLWeightedContainers.startEpoch();

        tVLWeightedContainers.updateContainerTVL(1, 20, 0, 10, true);
        tVLWeightedContainers.updateContainerTVL(2, 30, 0, 10, true);
        tVLWeightedContainers.updateContainerTVL(3, 50, 0, 10, true);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 5);
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 10);

        tVLWeightedContainers.setLastProcessedEpoch(1);

        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION());

        tVLWeightedContainers.updateContainerTVL(3, 150, 1, 10, true);
        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION() * 2);

        assertEq(tVLWeightedContainers.nextEpochToProcess(), 1);
        assertEq(tVLWeightedContainers.currentEpoch(), 2);

        tVLWeightedContainers.advanceEpoch(1000);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 4); // FAIL!
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 13);

        assertEq(tVLWeightedContainers.nextEpochToProcess(), 2);
        assertEq(tVLWeightedContainers.currentEpoch(), 2);

        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION() * 11);

        tVLWeightedContainers.advanceEpoch(1000);

        assertEq(tVLWeightedContainers.nextEpochToProcess(), 11);
        assertEq(tVLWeightedContainers.currentEpoch(), 11);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 1);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 11);

        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION() * 14);

        tVLWeightedContainers.advanceEpoch(1000);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 1);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 5);

        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION() * 15);

        tVLWeightedContainers.advanceEpoch(1000);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 1);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 4);

        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION() * 16);

        tVLWeightedContainers.advanceEpoch(1000);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 1);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 3);

        vm.warp(tVLWeightedContainers.initializedAtTimestamp() + tVLWeightedContainers.EPOCH_DURATION() * 17);

        tVLWeightedContainers.advanceEpoch(1000);

        assertEq(tVLWeightedContainers.getContainer(1).currentDurationEpochs, 1);
        assertEq(tVLWeightedContainers.getContainer(2).currentDurationEpochs, 2);
        assertEq(tVLWeightedContainers.getContainer(3).currentDurationEpochs, 3);
    }

    function test_Main_2() public {}
}
