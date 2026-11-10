// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {ITVLWeightedContainersErrors} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersCurrentEpoch is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    modifier givenEpochNotStarted() {
        // Epoch is not started by default
        _;
    }

    function test_RevertWhen_EpochNotStarted() external givenEpochNotStarted {
        // When initializedAtTimestamp is 0, currentEpoch() should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersNotStarted.selector);
        containers.currentEpoch();
    }

    modifier givenEpochStarted() {
        containers.activateContainer(1);
        containers.startEpoch();
        _;
    }

    function test_ReturnsZeroWhenCurrentTimeEqualsInitializedTimestamp() external givenEpochStarted {
        // The startEpoch sets initializedAtTimestamp to block.timestamp
        // Since we don't advance time, currentEpoch should return 0
        uint256 epoch = containers.currentEpoch();

        // it should return zero
        assertEq(epoch, 0);
    }

    function test_ReturnsZeroWhenCurrentTimeIsLessThanOneEpochDuration() external givenEpochStarted {
        // Advance time by less than one epoch (1 week - 1 second)
        vm.warp(block.timestamp + EPOCH_DURATION - 1);

        uint256 epoch = containers.currentEpoch();

        // it should return zero
        assertEq(epoch, 0);
    }

    function test_ReturnsCorrectEpochNumberWhenCurrentTimeSpansMultipleEpochs() external givenEpochStarted {
        // Test epoch 1
        vm.warp(block.timestamp + EPOCH_DURATION);
        uint256 epoch1 = containers.currentEpoch();
        assertEq(epoch1, 1);

        // Test epoch 5
        vm.warp(block.timestamp + EPOCH_DURATION * 4); // Total: 5 epochs
        uint256 epoch5 = containers.currentEpoch();
        assertEq(epoch5, 5);

        // Test epoch 10
        vm.warp(block.timestamp + EPOCH_DURATION * 5); // Total: 10 epochs
        uint256 epoch10 = containers.currentEpoch();
        assertEq(epoch10, 10);

        // Test partial epoch (should still be epoch 10)
        vm.warp(block.timestamp + EPOCH_DURATION / 2); // Total: 10.5 epochs
        uint256 epochPartial = containers.currentEpoch();
        assertEq(epochPartial, 10);

        // Test epoch 11
        vm.warp(block.timestamp + EPOCH_DURATION / 2 + 1); // Total: 11+ epochs
        uint256 epoch11 = containers.currentEpoch();
        assertEq(epoch11, 11);
    }

    function test_EpochCalculationConsistency() external givenEpochStarted {
        uint256 startTime = containers.initializedAtTimestamp();

        // Test boundary conditions
        for (uint256 i = 0; i < 5; i++) {
            // Exactly at epoch boundary
            vm.warp(startTime + EPOCH_DURATION * i);
            uint256 epochAtBoundary = containers.currentEpoch();
            assertEq(epochAtBoundary, i);

            // Just before next epoch
            vm.warp(startTime + EPOCH_DURATION * (i + 1) - 1);
            uint256 epochBeforeNext = containers.currentEpoch();
            assertEq(epochBeforeNext, i);
        }
    }

    function testFuzz_CurrentEpochCalculation(uint256 timeOffset) external givenEpochStarted {
        // Limit timeOffset to reasonable bounds (0 to 100 epochs)
        timeOffset = bound(timeOffset, 0, EPOCH_DURATION * 100);

        uint256 startTime = block.timestamp;
        vm.warp(startTime + timeOffset);

        uint256 expectedEpoch = timeOffset / EPOCH_DURATION;
        uint256 actualEpoch = containers.currentEpoch();

        assertEq(actualEpoch, expectedEpoch);
    }
}
