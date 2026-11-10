// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Container} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";

contract GetTotalTvlForEpochTest is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
        containers.activateContainer(1);
        containers.startEpoch();
    }

    function test_NoActiveContainers() public {
        // Deploy without any containers
        _deployWithoutContainers();
        // Can't start epoch without containers, so just test getTotalTvlForEpoch directly

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, 0);
    }

    function test_SingleActiveContainer_NoTVL() public view {
        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, 0);
    }

    function test_SingleActiveContainer_HasTVL() public {
        uint256 tvlAmount = 1000 ether;
        containers.updateContainerTVL(1, tvlAmount, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, tvlAmount);
    }

    function test_SingleActiveContainer_FutureEpoch() public {
        uint256 tvlAmount = 1000 ether;
        containers.updateContainerTVL(1, tvlAmount, 0, 1, true);

        // Query future epoch that hasn't been processed
        uint256 totalTvl = containers.getTotalTvlForEpoch(5);
        assertEq(totalTvl, 0);
    }

    modifier givenMultipleActiveContainersExist() {
        containers.activateContainer(containers.addContainer(defaultContainer));
        containers.activateContainer(containers.addContainer(defaultContainer));
        _;
    }

    function test_MultipleActiveContainers_NoTVL() public givenMultipleActiveContainersExist {
        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, 0);
    }

    function test_MultipleActiveContainers_OnlyOneHasTVL() public givenMultipleActiveContainersExist {
        // Only first container has TVL
        uint256 tvlAmount = 1500 ether;
        containers.updateContainerTVL(1, tvlAmount, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, tvlAmount);
    }

    function test_MultipleActiveContainers_AllHaveTVL() public givenMultipleActiveContainersExist {
        // All containers have TVL
        uint256 tvlAmount1 = 1000 ether;
        uint256 tvlAmount2 = 2000 ether;
        uint256 tvlAmount3 = 3000 ether;

        containers.updateContainerTVL(1, tvlAmount1, 0, 1, true);
        containers.updateContainerTVL(2, tvlAmount2, 0, 1, true);
        containers.updateContainerTVL(3, tvlAmount3, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, tvlAmount1 + tvlAmount2 + tvlAmount3);
    }

    function test_MultipleActiveContainers_DifferentTVLAmounts() public givenMultipleActiveContainersExist {
        // Different TVL amounts including some with zero
        uint256 tvlAmount1 = 100 ether;
        uint256 tvlAmount2 = 0; // Zero TVL
        uint256 tvlAmount3 = 5000 ether;

        containers.updateContainerTVL(1, tvlAmount1, 0, 1, true);
        // Don't add TVL for second container (remains zero)
        containers.updateContainerTVL(3, tvlAmount3, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, tvlAmount1 + tvlAmount2 + tvlAmount3);
    }

    function test_MixActiveInactiveContainers_BothHaveTVL() public {
        // Add inactive container and activate it
        containers.addContainer(defaultContainer);
        containers.activateContainer(2);
        // Give it some TVL and deactivate it
        containers.updateContainerTVL(2, 1000 ether, 0, 1, true);
        containers.deactivateContainer(2);

        // Add TVL to active container
        uint256 activeTvl = 1000 ether;
        containers.updateContainerTVL(1, activeTvl, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        // Should only count active container's TVL
        assertEq(totalTvl, activeTvl);
    }

    function test_MixActiveInactiveContainers_OnlyInactiveHasTVL() public {
        // Add inactive container and activate it
        containers.addContainer(defaultContainer);
        containers.activateContainer(2);
        // Give it some TVL and deactivate it
        containers.updateContainerTVL(2, 1000 ether, 0, 1, true);
        containers.deactivateContainer(2);

        // Only active container (1) is considered, inactive doesn't contribute
        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, 0);
    }

    function test_ContainersDeactivatedAfterHavingTVL() public {
        // Add and activate second container
        Container memory secondContainer = defaultContainer;
        uint256 secondId = containers.addContainer(secondContainer);
        containers.activateContainer(secondId);

        // Add TVL to both containers
        uint256 tvlAmount1 = 1000 ether;
        uint256 tvlAmount2 = 2000 ether;

        containers.updateContainerTVL(1, tvlAmount1, 0, 1, true);
        containers.updateContainerTVL(secondId, tvlAmount2, 0, 1, true);

        // Check total before deactivation
        uint256 totalTvlBefore = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlBefore, tvlAmount1 + tvlAmount2);

        // Deactivate second container
        containers.deactivateContainer(secondId);

        // Total TVL should now only include active container
        uint256 totalTvlAfter = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlAfter, tvlAmount1);
    }

    function test_HistoricalEpochs_DifferentActiveContainers() public {
        // Add TVL for epoch 0 and 1
        containers.updateContainerTVL(1, 1000 ether, 0, 2, true);

        // Activate second container and add TVL for epoch 0,1,2
        containers.activateContainer(containers.addContainer(defaultContainer));
        containers.updateContainerTVL(2, 1000 ether, 0, 3, true);

        vm.warp(containers.initializedAtTimestamp() + containers.EPOCH_DURATION() + 1);

        // We are now in epoch 1
        containers.advanceEpoch(0);
        uint256 totalTvlEpoch1_0 = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlEpoch1_0, 2000 ether);

        uint256 totalTvlEpoch1_1 = containers.getTotalTvlForEpoch(1);
        assertEq(totalTvlEpoch1_1, 2000 ether);

        vm.warp(containers.initializedAtTimestamp() + containers.EPOCH_DURATION() * 2 + 1);

        // We are now in epoch 2
        containers.advanceEpoch(0);
        uint256 totalTvlEpoch2_0 = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlEpoch2_0, 2000 ether);

        uint256 totalTvlEpoch2_1 = containers.getTotalTvlForEpoch(1);
        assertEq(totalTvlEpoch2_1, 2000 ether);

        // Container 1 does not have TVL in epoch 2
        uint256 totalTvlEpoch2_2 = containers.getTotalTvlForEpoch(2);
        assertEq(totalTvlEpoch2_2, 1000 ether);

        // Deactivate container 1 and see if historical TVL is affected
        containers.deactivateContainer(1);

        uint256 totalTvlEpoch2_0_after = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlEpoch2_0_after, 1000 ether);

        uint256 totalTvlEpoch2_1_after = containers.getTotalTvlForEpoch(1);
        assertEq(totalTvlEpoch2_1_after, 1000 ether);

        uint256 totalTvlEpoch2_2_after = containers.getTotalTvlForEpoch(2);
        assertEq(totalTvlEpoch2_2_after, 1000 ether);
    }

    function test_HistoricalEpochs_NoTVLData() public {
        vm.warp(containers.initializedAtTimestamp() + containers.EPOCH_DURATION() * 10 + 1);
        containers.advanceEpoch(0);

        // Query epoch that never had any TVL data
        uint256 totalTvl = containers.getTotalTvlForEpoch(5);
        assertEq(totalTvl, 0);
    }

    function test_TVLUpdates_AddAndSubtract() public {
        // Add initial TVL
        uint256 initialTvl = 1000 ether;
        containers.updateContainerTVL(1, initialTvl, 0, 1, true);

        uint256 totalTvlAfterAdd = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlAfterAdd, initialTvl);

        // Subtract some TVL
        uint256 subtractAmount = 300 ether;
        containers.updateContainerTVL(1, subtractAmount, 0, 1, false);

        uint256 totalTvlAfterSubtract = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvlAfterSubtract, initialTvl - subtractAmount);
    }

    function test_MaxActiveContainers_TVL() public {
        // Create maximum number of active containers (16)
        Container[] memory containers_array = new Container[](16);
        for (uint256 i = 0; i < 16; i++) {
            containers_array[i] = defaultContainer;
        }

        _deployWithContainers(containers_array);

        // Activate all containers
        for (uint256 i = 1; i <= 16; i++) {
            containers.activateContainer(i);
        }

        containers.startEpoch();

        // Add TVL to all containers
        uint256 tvlPerContainer = 100 ether;
        for (uint256 i = 1; i <= 16; i++) {
            containers.updateContainerTVL(i, tvlPerContainer, 0, 1, true);
        }

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, tvlPerContainer * 16);
    }

    function testFuzz_GetTotalTvlForEpoch(uint8 numContainers, uint256 epoch, uint256 baseTvlAmount) public {
        numContainers = uint8(bound(numContainers, 1, containers.MAX_ACTIVE_CONTAINERS()));
        epoch = bound(epoch, 0, 10);
        baseTvlAmount = bound(baseTvlAmount, 0, 1000000 ether);

        // Create and activate containers
        if (numContainers > 1) {
            Container[] memory containers_array = new Container[](numContainers);
            for (uint256 i = 0; i < numContainers; i++) {
                containers_array[i] = defaultContainer;
            }

            _deployWithContainers(containers_array);

            for (uint256 i = 1; i <= numContainers; i++) {
                containers.activateContainer(i);
            }

            containers.startEpoch();
        } else {
            // For single container, use the setup's existing deployed container
            // which is already activated and epoch started
        }

        uint256 expectedTotal = 0;

        // Add TVL to containers for epoch 0 only
        if (epoch == 0 && baseTvlAmount > 0) {
            for (uint256 i = 1; i <= numContainers; i++) {
                uint256 containerTvl = baseTvlAmount / numContainers;
                if (containerTvl > 0) {
                    containers.updateContainerTVL(i, containerTvl, 0, 1, true);
                    expectedTotal += containerTvl;
                }
            }
        }

        uint256 totalTvl = containers.getTotalTvlForEpoch(epoch);

        if (epoch == 0) {
            assertEq(totalTvl, expectedTotal);
        } else {
            // Future epochs should have zero TVL
            assertEq(totalTvl, 0);
        }
    }

    function test_EdgeCase_ZeroTVLContainerAmongNonZero() public givenMultipleActiveContainersExist {
        // Add TVL to first and third containers, leave second with zero
        containers.updateContainerTVL(1, 1000 ether, 0, 1, true);
        // container 2 gets no TVL (remains zero)
        containers.updateContainerTVL(3, 2000 ether, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, 3000 ether);
    }

    function test_EdgeCase_VeryLargeTVLAmounts() public {
        // Test with very large TVL amounts
        uint256 largeTvl = type(uint256).max / 2;

        containers.updateContainerTVL(1, largeTvl, 0, 1, true);
        containers.addContainer(defaultContainer);
        containers.activateContainer(2);
        containers.updateContainerTVL(2, largeTvl, 0, 1, true);

        uint256 totalTvl = containers.getTotalTvlForEpoch(0);
        assertEq(totalTvl, largeTvl * 2);
    }
}
