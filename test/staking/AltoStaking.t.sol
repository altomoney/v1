// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockAltoStaking} from "@alto-test/staking/helpers/MockAltoStaking.sol";

contract AltoStaking_Main is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable USER = makeAddr("User");
    address internal immutable USER_2 = makeAddr("User_2");

    MockAltoStaking altoStaking;
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

        altoStaking =
            new MockAltoStaking(address(lockToken), OWNER, 1 days, initialContainers, initialContainerMultipliers);

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

    function test_MainStaking() public {
        altoStaking.lock(USER, 1 ether, 1, false, 0);

        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 1 ether);
        assertEq(altoStaking.getPosition(USER, 1).expiryTimestamp, block.timestamp + 1 days);
        assertEq(altoStaking.getPosition(USER, 1).lockedTimestamp, block.timestamp);

        assertEq(altoStaking.getVotes(USER), 0.3 ether);
    }

    function test_MainStaking_2() public {
        altoStaking.lock(USER, 1 ether, 1, false, 0);

        Container memory container = altoStaking.getContainer(1);
        uint256 containerDuration = container.currentDurationEpochs;
        uint256 timestampDuration = altoStaking.EPOCH_DURATION();
        uint256 initTimestamp = altoStaking.initializedAtTimestamp();

        assertEq(containerDuration, 1);

        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 1 ether);
        assertEq(
            altoStaking.getPosition(USER, 1).expiryTimestamp, block.timestamp + containerDuration * timestampDuration
        );
        assertEq(altoStaking.getPosition(USER, 1).lockedTimestamp, block.timestamp);

        assertEq(altoStaking.getVotes(USER), 0.3 ether);

        uint256 balanceBeforeStaking2 = lockToken.balanceOf(address(altoStaking));
        uint256 balanceBeforeUser2 = lockToken.balanceOf(address(this));

        altoStaking.lock(USER_2, 100 ether, 1, false, 0);

        uint256 balanceAfterStaking2 = lockToken.balanceOf(address(altoStaking));
        uint256 balanceAfterUser2 = lockToken.balanceOf(address(this));

        assertEq(balanceAfterStaking2, balanceBeforeStaking2 + 100 ether);
        assertEq(balanceAfterUser2, balanceBeforeUser2 - 100 ether);

        assertEq(altoStaking.getPosition(USER_2, 1).amountLocked, 100 ether);
        assertEq(
            altoStaking.getPosition(USER_2, 1).expiryTimestamp, block.timestamp + containerDuration * timestampDuration
        );
        assertEq(altoStaking.getPosition(USER_2, 1).lockedTimestamp, block.timestamp);

        assertEq(altoStaking.getVotes(USER_2), 30 ether);

        vm.warp(block.timestamp + timestampDuration);

        altoStaking.advanceEpoch(1);

        Container memory containerAfter = altoStaking.getContainer(1);
        uint256 containerDurationAfter = containerAfter.currentDurationEpochs;

        assertEq(containerDurationAfter, 4);

        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 1 ether);
        assertEq(
            altoStaking.getPosition(USER, 1).expiryTimestamp, initTimestamp + containerDuration * timestampDuration
        );

        assertGe(altoStaking.getPosition(USER, 1).expiryTimestamp, block.timestamp);

        assertEq(altoStaking.getVotes(USER), 0);
    }

    function test_MainStaking_3() public {
        test_MainStaking_2();

        Container memory container = altoStaking.getContainer(1);
        uint256 containerDuration = container.currentDurationEpochs;
        uint256 timestampDuration = altoStaking.EPOCH_DURATION();
        uint256 initTimestamp = altoStaking.initializedAtTimestamp();

        uint256 balanceBeforeStaking = lockToken.balanceOf(address(altoStaking));
        uint256 balanceBeforeUser = lockToken.balanceOf(address(this));

        altoStaking.lock(USER, 1 ether, 1, true, 0);

        uint256 balanceAfterStaking = lockToken.balanceOf(address(altoStaking));
        uint256 balanceAfterUser = lockToken.balanceOf(address(this));

        assertEq(balanceAfterStaking, balanceBeforeStaking);
        assertEq(balanceAfterUser, balanceBeforeUser);

        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 1 ether);
        assertEq(
            altoStaking.getPosition(USER, 1).expiryTimestamp, block.timestamp + (containerDuration * timestampDuration)
        );
        assertEq(altoStaking.getPosition(USER, 1).lockedTimestamp, block.timestamp);

        assertEq(altoStaking.getVotes(USER), 0.3 ether);
    }

    function test_MainStaking_4() public {
        test_MainStaking_2();

        uint256 balanceBeforeStaking = lockToken.balanceOf(address(altoStaking));
        uint256 balanceBeforeUser = lockToken.balanceOf(USER);

        altoStaking.unlock(USER, USER, 1);

        uint256 balanceAfterStaking = lockToken.balanceOf(address(altoStaking));
        uint256 balanceAfterUser = lockToken.balanceOf(USER);

        assertEq(balanceAfterStaking, balanceBeforeStaking - 1 ether);
        assertEq(balanceAfterUser, balanceBeforeUser + 1 ether);

        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 0);
        assertEq(altoStaking.getPosition(USER, 1).expiryTimestamp, 0);
        assertEq(altoStaking.getPosition(USER, 1).lockedTimestamp, 0);

        assertEq(altoStaking.getVotes(USER), 0);
    }

    function test_MainStaking_5() public {
        vm.warp(block.timestamp + altoStaking.EPOCH_DURATION() / 4); // Half an epoch

        // Initial lock: 100 tokens in container 1 for 1 epoch (current duration)
        altoStaking.lock(USER, 100 ether, 1, false, 0);
        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 100 ether, "Position should show 100 ether total");

        // Check initial TVL in epoch 0
        uint256 initialTVL = altoStaking.epochTVL(altoStaking.currentEpoch(), 1);
        assertEq(initialTVL, 100 ether, "Initial TVL should be 100 ether");

        // Move forward in time but stay within the same epoch
        vm.warp(block.timestamp + altoStaking.EPOCH_DURATION() / 2); // Half an epoch

        // Lock more tokens to the same position (this should extend/modify the position)
        altoStaking.lock(USER, 50 ether, 1, false, 0); // Total becomes 150 ether

        // Check TVL after extending - this should be 150 ether total, not more
        uint256 newTVL = altoStaking.epochTVL(altoStaking.currentEpoch(), 1);

        // TVL should be 150 ether total, not double counted
        assertEq(newTVL, 150 ether, "TVL should be 150 ether total, not double counted");

        // Additional check: verify the position shows correct total
        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 150 ether, "Position should show 150 ether total");
    }

    function test_MainStaking_6() public {
        uint256 CONTAINER_ID = 1;
        vm.warp(altoStaking.initializedAtTimestamp() + 60 minutes);

        // Initial lock: 100 tokens in container 1 for 1 epoch (current duration)
        altoStaking.lock(USER, 100 ether, CONTAINER_ID, false, 0);
        assertEq(
            altoStaking.getPosition(USER, CONTAINER_ID).amountLocked, 100 ether, "Position should show 100 ether total"
        );

        uint256 firstEpoch = altoStaking.currentEpoch();

        assertEq(firstEpoch, 0);

        // Check initial TVL in epoch 0
        uint256 initialTVL = altoStaking.epochTVL(firstEpoch, CONTAINER_ID);
        assertEq(initialTVL, 100 ether, "Initial TVL should be 100 ether");

        vm.warp(altoStaking.initializedAtTimestamp() + altoStaking.EPOCH_DURATION() + 10 minutes);

        // Lock more tokens to the same position (this should extend/modify the position)
        altoStaking.lock(USER, 50 ether, CONTAINER_ID, false, 0); // Total becomes 150 ether

        assertEq(altoStaking.currentEpoch(), firstEpoch + 1);

        // Check TVL after extending - this should be 150 ether total, not more
        uint256 newTVL = altoStaking.epochTVL(altoStaking.currentEpoch(), CONTAINER_ID);

        // TVL should be 150 ether total, not double counted
        assertEq(newTVL, 150 ether, "TVL should be 150 ether total, not double counted");

        uint256 newTVLPrevEpoch = altoStaking.epochTVL(firstEpoch, CONTAINER_ID);
        assertEq(newTVLPrevEpoch, 100 ether);

        uint256 newTVLCurrentEpoch = altoStaking.epochTVL(firstEpoch + 1, CONTAINER_ID);
        assertEq(newTVLCurrentEpoch, 150 ether);

        // Additional check: verify the position shows correct total
        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 150 ether, "Position should show 150 ether total");
    }

    function test_MainStaking_7() public {
        uint256 CONTAINER_ID = 1;
        vm.warp(altoStaking.initializedAtTimestamp() + 60 minutes);

        // Initial lock: 100 tokens in container 1 for 1 epoch (current duration)
        altoStaking.lock(USER, 100 ether, CONTAINER_ID, false, 0);
        assertEq(
            altoStaking.getPosition(USER, CONTAINER_ID).amountLocked, 100 ether, "Position should show 100 ether total"
        );

        uint256 firstEpoch = altoStaking.currentEpoch();

        assertEq(firstEpoch, 0);

        // Check initial TVL in epoch 0
        uint256 initialTVL = altoStaking.epochTVL(firstEpoch, CONTAINER_ID);
        assertEq(initialTVL, 100 ether, "Initial TVL should be 100 ether");

        vm.warp(altoStaking.getPosition(USER, CONTAINER_ID).expiryTimestamp + 1);

        // Lock more tokens to the same position (this should extend/modify the position)
        altoStaking.unlock(USER, USER, CONTAINER_ID);
        altoStaking.lock(USER, 50 ether, CONTAINER_ID, false, 0); // Total becomes 150 ether

        assertEq(altoStaking.currentEpoch(), firstEpoch + 1);

        // Check TVL after extending - this should be 150 ether total, not more
        uint256 newTVL = altoStaking.epochTVL(altoStaking.currentEpoch(), CONTAINER_ID);

        // TVL should be 150 ether total, not double counted
        assertEq(newTVL, 50 ether, "TVL should be 150 ether total, not double counted");

        uint256 newTVLPrevEpoch = altoStaking.epochTVL(firstEpoch, CONTAINER_ID);
        assertEq(newTVLPrevEpoch, 100 ether);

        uint256 newTVLCurrentEpoch = altoStaking.epochTVL(firstEpoch + 1, CONTAINER_ID);
        assertEq(newTVLCurrentEpoch, 50 ether);

        // Additional check: verify the position shows correct total
        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 50 ether, "Position should show 150 ether total");
    }

    function test_MainStaking_8() public {
        uint256 CONTAINER_ID = 1;
        vm.warp(altoStaking.initializedAtTimestamp() + 60 minutes);

        // Initial lock: 100 tokens in container 1 for 1 epoch (current duration)
        altoStaking.lock(USER, 100 ether, CONTAINER_ID, false, 0);
        assertEq(
            altoStaking.getPosition(USER, CONTAINER_ID).amountLocked, 100 ether, "Position should show 100 ether total"
        );

        uint256 firstEpoch = altoStaking.currentEpoch();

        assertEq(firstEpoch, 0);

        // Check initial TVL in epoch 0
        uint256 initialTVL = altoStaking.epochTVL(firstEpoch, CONTAINER_ID);
        assertEq(initialTVL, 100 ether, "Initial TVL should be 100 ether");

        vm.warp(altoStaking.getPosition(USER, CONTAINER_ID).expiryTimestamp + 1);

        // Lock more tokens to the same position (this should extend/modify the position)
        altoStaking.lock(USER, 100 ether, CONTAINER_ID, true, 0); // Total becomes 150 ether

        assertEq(altoStaking.currentEpoch(), firstEpoch + 1);

        // Check TVL after extending - this should be 150 ether total, not more
        uint256 newTVL = altoStaking.epochTVL(altoStaking.currentEpoch(), CONTAINER_ID);

        // TVL should be 150 ether total, not double counted
        assertEq(newTVL, 100 ether, "TVL should be 150 ether total, not double counted");

        uint256 newTVLPrevEpoch = altoStaking.epochTVL(firstEpoch, CONTAINER_ID);
        assertEq(newTVLPrevEpoch, 100 ether);

        uint256 newTVLCurrentEpoch = altoStaking.epochTVL(firstEpoch + 1, CONTAINER_ID);
        assertEq(newTVLCurrentEpoch, 100 ether);

        // Additional check: verify the position shows correct total
        assertEq(altoStaking.getPosition(USER, 1).amountLocked, 100 ether, "Position should show 150 ether total");
    }
}
