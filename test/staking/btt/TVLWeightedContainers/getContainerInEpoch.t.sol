// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Container} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";

contract GetContainerInEpochTest is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
        containers.activateContainer(1);
        containers.startEpoch();
    }

    function test_EpochSystemNotStarted() public {
        _deployWithSingleContainer();
        containers.activateContainer(1);
        // Don't start epoch system

        // getContainerInEpoch calls _getTotalTvlForEpoch internally which doesn't check epoch started
        // So this test should actually pass without reverting
        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(1, 0);

        // Should return container data but with default calculations
        assertEq(container.duration.min, defaultContainer.duration.min);
        assertGe(duration, container.duration.min);
    }

    function test_ContainerDoesNotExist() public view {
        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(999, 0);

        // Non-existent container should return empty data
        assertEq(container.growthRate.min, 0);
        assertEq(container.growthRate.max, 0);
        assertEq(container.decayRate.min, 0);
        assertEq(container.decayRate.max, 0);
        assertEq(container.duration.min, 0);
        assertEq(container.duration.max, 0);
        assertFalse(container.isActive);
        assertEq(container.maxRateDifferenceEpochs, 0);
        assertEq(container.currentDurationEpochs, 0);
        assertEq(duration, 0);
    }

    function test_ContainerExistsButNotActive_NoTVL() public {
        uint256 inactiveId = containers.addContainer(defaultContainer);

        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(inactiveId, 0);

        // Inactive container should return minimum duration
        assertEq(duration, container.duration.min);
    }

    function test_ContainerExistsButNotActive_WithTVL() public {
        uint256 inactiveId = containers.addContainer(defaultContainer);

        // Add TVL for current epoch (this shouldn't affect inactive container)
        containers.updateContainerTVL(1, 1000 ether, 0, 1, true);

        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(inactiveId, 0);

        // Inactive container should still return minimum duration
        assertEq(duration, container.duration.min);
    }

    function test_ActiveContainer_NoTVLData() public view {
        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(1, 0);

        // With no TVL data, should return minimum duration
        assertEq(duration, container.duration.min);
    }

    function test_ActiveContainer_OnlyThisContainerHasTVL_CausesGrowth() public {
        // Set up container with specific parameters for predictable growth
        ContainerParams memory params = ContainerParams({
            growthMin: 2,
            growthMax: 10,
            decayMin: 1,
            decayMax: 5,
            durationMin: 20,
            durationMax: 200,
            maxRateDifference: 100
        });
        Container memory customContainer = _createContainerWithCustomParams(params);

        _deployWithoutContainers();
        uint256 containerId = containers.addContainer(customContainer);
        containers.activateContainer(containerId);
        containers.startEpoch();

        // Add significant TVL to trigger growth
        containers.updateContainerTVL(containerId, 1000 ether, 0, 1, true);

        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(containerId, 0);

        // As it's the only container it should grow max growth rate 10 epochs
        assertEq(duration, container.duration.min + params.growthMax);

        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);
        containers.advanceEpoch(1);

        (Container memory containerAfter) = containers.getContainer(containerId);

        assertEq(containerAfter.currentDurationEpochs, duration);
    }

    function test_ActiveContainer_OnlyThisContainerHasTVL_CausesDecay() public {
        // Set up container for predicting decay
        ContainerParams memory params = ContainerParams({
            growthMin: 1,
            growthMax: 5,
            decayMin: 2,
            decayMax: 8,
            durationMin: 20,
            durationMax: 200,
            maxRateDifference: 100
        });
        Container memory customContainer = _createContainerWithCustomParams(params);

        _deployWithoutContainers();
        uint256 containerId_1 = containers.addContainer(customContainer);
        containers.activateContainer(containerId_1);
        uint256 containerId_2 = containers.addContainer(customContainer);
        containers.activateContainer(containerId_2);
        containers.startEpoch();

        // Add significant TVL to trigger growth first
        containers.updateContainerTVL(containerId_1, 1 ether, 0, 1, true);

        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(containerId_1, 0);

        // As it's the only container it should grow max growth rate 10 epochs
        assertEq(duration, container.duration.min + params.growthMax);

        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);
        containers.advanceEpoch(1);

        (Container memory containerAfter) = containers.getContainer(containerId_1);

        assertEq(containerAfter.currentDurationEpochs, duration);

        // Add high TVL to second container to trigger decay on the first
        containers.updateContainerTVL(containerId_2, 100000000000 ether, 1, 2, true);

        (, uint24 durationAfterTvlChange) = containers.getContainerAfterEpochProcessing(containerId_1, 1);

        // We expect decay of 2 epochs
        assertEq(durationAfterTvlChange, containerAfter.currentDurationEpochs - 2);

        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION * 2 + 1);
        containers.advanceEpoch(1);

        (Container memory containerAfterDecay) = containers.getContainer(containerId_1);

        assertEq(containerAfterDecay.currentDurationEpochs, durationAfterTvlChange);
    }

    function test_ActiveContainer_MultipleContainers_MajorityTVLShare() public {
        // Create second container
        uint256 secondId = containers.addContainer(defaultContainer);
        containers.activateContainer(secondId);

        // Container 1 gets majority of TVL
        containers.updateContainerTVL(1, 800 ether, 0, 1, true);
        containers.updateContainerTVL(secondId, 200 ether, 0, 1, true);

        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(1, 0);
        (Container memory container2, uint24 duration2) = containers.getContainerAfterEpochProcessing(2, 0);
        // Both containes shoul grow
        assertGe(duration, container.duration.min);
        assertGe(duration2, container2.duration.min);

        // Container 1 should grow faster than the container 2
        assertGe(duration, duration2);
    }

    function test_ActiveContainer_MultipleContainers_EqualTVLShare() public {
        // Create second container
        uint256 secondId = containers.addContainer(defaultContainer);
        containers.activateContainer(secondId);

        // Equal TVL distribution
        containers.updateContainerTVL(1, 500 ether, 0, 1, true);
        containers.updateContainerTVL(secondId, 500 ether, 0, 1, true);

        (, uint24 duration1) = containers.getContainerAfterEpochProcessing(1, 0);
        (, uint24 duration2) = containers.getContainerAfterEpochProcessing(secondId, 0);

        // Both containers should have same calculated duration with equal TVL shares
        assertEq(duration1, duration2);
    }

    function test_ContainerDuration_ExceedsMaximum() public {
        // Set up container with small range to easily exceed maximum
        ContainerParams memory params = ContainerParams({
            growthMin: 20,
            growthMax: 50,
            decayMin: 1,
            decayMax: 3,
            durationMin: 10,
            durationMax: 50, // Small maximum
            maxRateDifference: 40 // Must be <= duration.max (50)
        });
        Container memory customContainer = _createContainerWithCustomParams(params);

        _deployWithoutContainers();
        uint256 containerId = containers.addContainer(customContainer);
        containers.activateContainer(containerId);
        containers.startEpoch();

        // Set current duration close to max
        containers.setContainerLockDuration(containerId, 45);

        // Add large TVL to trigger growth that would exceed maximum
        containers.updateContainerTVL(containerId, 10000 ether, 0, 1, true);

        (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(containerId, 0);

        // Duration should be capped at maximum
        assertEq(duration, container.duration.max);
    }

    function testFuzz_GetContainerInEpoch(
        uint256 containerId,
        uint256 epoch,
        uint256 tvlAmount,
        uint256 currentDurationInput
    ) public {
        // Bound inputs
        containerId = bound(containerId, 1, 10);
        epoch = bound(epoch, 0, 100);
        tvlAmount = bound(tvlAmount, 0, 1000000 ether);
        uint24 currentDuration =
            uint24(bound(currentDurationInput, defaultContainer.duration.min, defaultContainer.duration.max));

        // Ensure container exists and is active if we're testing with container ID 1
        if (containerId == 1) {
            if (tvlAmount > 0) {
                containers.updateContainerTVL(1, tvlAmount, 0, 1, true);
            }
            containers.setContainerLockDuration(1, currentDuration);

            (Container memory container, uint24 duration) = containers.getContainerAfterEpochProcessing(1, epoch);

            // Basic invariants
            assertGe(duration, container.duration.min);
            assertLe(duration, container.duration.max);
        } else {
            // For non-existent containers, should return empty data
            (Container memory container, uint24 duration) =
                containers.getContainerAfterEpochProcessing(containerId, epoch);
            assertEq(container.duration.min, 0);
            assertEq(duration, 0);
        }
    }
}
