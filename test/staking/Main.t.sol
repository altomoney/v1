// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {MockTVLWeightedContainersMock} from "@alto-test/staking/helpers/MockTVLWeightedContainersMock.sol";

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

        MockTVLWeightedContainersMock tVLWeightedContainers =
            new MockTVLWeightedContainersMock(1 days, initialContainers);

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
