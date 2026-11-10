// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {AltoStaking} from "@alto/staking/AltoStaking.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {IAltoStaking} from "@alto/staking/interfaces/IAltoStaking.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract AltoStaking_Gas is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable USER = makeAddr("User");
    address internal immutable USER_2 = makeAddr("User_2");

    IAltoStaking altoStaking;
    AltoStaking altoStakingImpl;
    ERC20Mock lockToken;

    function setUp() public {
        lockToken = new ERC20Mock("Lock Token", "LOCK");

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

        uint256[] memory initialContainerMultipliers = new uint256[](3);
        initialContainerMultipliers[0] = 0.3 ether;
        initialContainerMultipliers[1] = 0.6 ether;
        initialContainerMultipliers[2] = 1 ether;

        altoStakingImpl =
            new AltoStaking(address(lockToken), OWNER, 1 days, initialContainers, initialContainerMultipliers);
        altoStaking = IAltoStaking(address(altoStakingImpl));

        deal(address(lockToken), address(this), type(uint256).max);
        lockToken.approve(address(altoStaking), type(uint256).max);

        vm.startPrank(OWNER);
        altoStaking.activateContainer(1);
        altoStaking.activateContainer(2);
        altoStaking.activateContainer(3);
        altoStaking.startEpoch();
        vm.stopPrank();

        vm.prank(USER);
        altoStaking.setAuthorization(address(this), true);

        vm.prank(USER_2);
        altoStaking.setAuthorization(address(this), true);
    }

    function test_Gas_AdvanceEpoch_WorstCase() public {
        // Setup maximum number of containers (16) with varying configurations
        Container memory container;
        uint256[] memory multipliers = new uint256[](13); // We already have 3, need 13 more

        // Create 13 additional containers with different parameters to reach max of 16
        for (uint256 i = 0; i < 13; i++) {
            uint24 growthMin = uint24(1 + (i % 2));
            uint24 growthMax = uint24(growthMin + 1 + (i % 3));
            uint24 decayMin = uint24(1 + (i % 2));
            uint24 decayMax = uint24(decayMin + 1 + (i % 2));
            uint24 durationMin = uint24(2 + (i % 3));
            uint24 durationMax = uint24(durationMin + 5 + (i % 8));

            container = Container({
                growthRate: MinMaxEpochs({min: growthMin, max: growthMax}),
                decayRate: MinMaxEpochs({min: decayMin, max: decayMax}),
                duration: MinMaxEpochs({min: durationMin, max: durationMax}),
                maxRateDifferenceEpochs: uint24(Math.min(4 + (i % 4), durationMax)),
                currentDurationEpochs: 0,
                isActive: false
            });

            multipliers[i] = 0.1 ether + (i * 0.05 ether); // Varying multipliers

            vm.prank(OWNER);
            altoStaking.addContainer(container, multipliers[i]);

            vm.prank(OWNER);
            altoStaking.activateContainer(4 + i); // Container IDs start from 4 (we have 1,2,3 already)
        }

        // Verify we have 16 active containers
        assertEq(altoStakingImpl.activeContainerIds(0), 1, "First container should be active");
        // Note: We can't easily check the full length without a getter, but we know we activated 16

        // Create significant TVL for all containers to ensure they all need processing
        uint256 lockAmount = 100_000 ether;
        uint256 totalTokensNeeded = 0;

        // Calculate total tokens needed
        for (uint256 i = 0; i < 16; i++) {
            totalTokensNeeded += lockAmount + (i * 10_000 ether);
        }

        deal(address(lockToken), address(this), totalTokensNeeded * 2); // Extra buffer

        // Lock tokens in all 16 containers with different amounts to create varied TVL
        for (uint256 i = 0; i < 16; i++) {
            uint256 containerId = i + 1;
            uint256 amount = lockAmount + (i * 10_000 ether); // Varying amounts

            altoStaking.lock(USER, amount, containerId, false, 0);
        }

        // Fast forward time to create multiple epochs that need processing
        // This creates the worst case where many epochs need to be processed at once
        uint256 epochsToSkip = 5; // Process 5 epochs at once
        vm.warp(block.timestamp + (epochsToSkip * 1 days));

        // Measure gas for the worst-case advance epoch scenario
        uint256 gasBefore = gasleft();
        altoStaking.advanceEpoch(epochsToSkip);
        uint256 gasUsed = gasBefore - gasleft();

        // Log the gas consumption for analysis
        emit log_named_uint("Gas used for worst-case advanceEpoch", gasUsed);

        // Additional test: Advance epoch with unlimited limit to process all remaining epochs
        // Fast forward more time
        vm.warp(block.timestamp + (3 * 1 days));

        gasBefore = gasleft();
        altoStaking.advanceEpoch(0); // 0 means unlimited
        gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for unlimited advanceEpoch", gasUsed);

        // Test edge case: All containers need maximum changes
        // Lock additional amounts to create maximum TVL imbalance
        uint256 additionalAmount = 50_000 ether; // Large amount to trigger max changes
        deal(address(lockToken), address(this), additionalAmount * 16);

        for (uint256 i = 0; i < 16; i++) {
            uint256 containerId = i + 1;
            altoStaking.lock(USER_2, additionalAmount, containerId, false, 0);
        }

        // Fast forward and measure gas again
        vm.warp(block.timestamp + (2 * 1 days));

        gasBefore = gasleft();
        altoStaking.advanceEpoch(2);
        gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used after major TVL changes", gasUsed);
    }

    function test_Gas_AdvanceEpoch_SingleEpoch_MaxContainers() public {
        // Test gas consumption for advancing just one epoch with max containers
        Container memory container;

        // Create 13 additional containers to reach max of 16
        for (uint256 i = 0; i < 13; i++) {
            container = Container({
                growthRate: MinMaxEpochs({min: 1, max: 3}),
                decayRate: MinMaxEpochs({min: 1, max: 2}),
                duration: MinMaxEpochs({min: 2, max: 15}),
                maxRateDifferenceEpochs: 5,
                currentDurationEpochs: 0,
                isActive: false
            });

            vm.prank(OWNER);
            altoStaking.addContainer(container, 0.5 ether);

            vm.prank(OWNER);
            altoStaking.activateContainer(4 + i);
        }

        // Create TVL in all containers
        uint256 lockAmount = 50_000 ether;
        for (uint256 i = 0; i < 16; i++) {
            altoStaking.lock(USER, lockAmount, i + 1, false, 0);
        }

        // Fast forward one epoch
        vm.warp(block.timestamp + 1 days);

        // Measure gas for single epoch advancement
        uint256 gasBefore = gasleft();
        altoStaking.advanceEpoch(1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for single epoch with max containers", gasUsed);
    }
}
