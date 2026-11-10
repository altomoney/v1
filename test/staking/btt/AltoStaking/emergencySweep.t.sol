// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoStakingCommon, PAUSE_TYPE} from "./AltoStakingCommon.t.sol";
import {IAltoStakingErrors, IAltoStakingEvents} from "@alto/staking/interfaces/IAltoStaking.sol";

contract AltoStakingEmergencySweep is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _setupStandardStaking();

        // Create some positions to have tokens in the contract
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
        _lockPosition(USER_2, LOCK_AMOUNT * 2, 2, false);
    }

    function test_RevertGiven_ContractIsNotPaused() external {
        // Contract is not paused by default

        // it should revert
        vm.prank(OWNER);
        vm.expectRevert(IAltoStakingErrors.AltoStakingNotPausedForEmergencySweep.selector);
        staking.emergencySweep();
    }

    function test_RevertGiven_CallerIsNotOwner() external {
        // Pause the contract first
        _pauseContract();

        // it should revert
        vm.expectRevert();
        staking.emergencySweep();
    }

    modifier givenValidConditions() {
        _pauseContract();
        _;
    }

    function test_GivenValidConditions() external givenValidConditions {
        uint256 contractBalance = lockToken.balanceOf(address(staking));
        uint256 ownerBalanceBefore = lockToken.balanceOf(OWNER);

        assertTrue(contractBalance > 0, "Contract should have balance from locked positions");

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.EmergencySweep(OWNER, OWNER, contractBalance);

        vm.prank(OWNER);
        staking.emergencySweep();

        // it should transfer all contract balance to owner
        assertEq(lockToken.balanceOf(OWNER), ownerBalanceBefore + contractBalance);

        // it should leave contract with zero balance
        assertEq(lockToken.balanceOf(address(staking)), 0);
    }

    function test_EmergencySweepWithNoBalance() external givenValidConditions {
        // First sweep to empty the contract
        vm.prank(OWNER);
        staking.emergencySweep();

        // Contract should now have zero balance
        assertEq(lockToken.balanceOf(address(staking)), 0);

        // Second sweep should still work but transfer 0 tokens
        uint256 ownerBalanceBefore = lockToken.balanceOf(OWNER);

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.EmergencySweep(OWNER, OWNER, 0);

        vm.prank(OWNER);
        staking.emergencySweep();

        assertEq(lockToken.balanceOf(OWNER), ownerBalanceBefore);
        assertEq(lockToken.balanceOf(address(staking)), 0);
    }

    function test_EmergencySweepMultipleTimes() external givenValidConditions {
        uint256 initialContractBalance = lockToken.balanceOf(address(staking));
        uint256 ownerBalanceBefore = lockToken.balanceOf(OWNER);

        // First sweep
        vm.prank(OWNER);
        staking.emergencySweep();

        assertEq(lockToken.balanceOf(OWNER), ownerBalanceBefore + initialContractBalance);
        assertEq(lockToken.balanceOf(address(staking)), 0);

        // Add more tokens to contract (simulate additional deposits)
        deal(address(lockToken), address(staking), LOCK_AMOUNT);

        uint256 newContractBalance = lockToken.balanceOf(address(staking));
        uint256 ownerBalanceAfterFirst = lockToken.balanceOf(OWNER);

        // Second sweep
        vm.prank(OWNER);
        staking.emergencySweep();

        assertEq(lockToken.balanceOf(OWNER), ownerBalanceAfterFirst + newContractBalance);
        assertEq(lockToken.balanceOf(address(staking)), 0);
    }

    function test_EmergencySweepAfterUnlocks() external givenValidConditions {
        // Record initial state
        uint256 initialContractBalance = lockToken.balanceOf(address(staking));

        // Unpause temporarily to allow unlocks
        vm.prank(PAUSER);
        staking.pause(PAUSE_TYPE, false);

        // Enable rescue mode to allow early unlock
        _enableRescueMode();

        // Unlock one position
        _unlockPosition(USER, RECEIVER, 1);

        uint256 contractBalanceAfterUnlock = lockToken.balanceOf(address(staking));
        assertTrue(contractBalanceAfterUnlock < initialContractBalance, "Balance should decrease after unlock");

        // Pause again for emergency sweep
        vm.prank(PAUSER);
        staking.pause(PAUSE_TYPE, true);

        // Emergency sweep should work with remaining balance
        uint256 ownerBalanceBefore = lockToken.balanceOf(OWNER);

        vm.prank(OWNER);
        staking.emergencySweep();

        assertEq(lockToken.balanceOf(OWNER), ownerBalanceBefore + contractBalanceAfterUnlock);
        assertEq(lockToken.balanceOf(address(staking)), 0);
    }

    function test_EmergencySweepPreciseBalance() external givenValidConditions {
        // Test with specific precise amounts
        uint256 contractBalance = lockToken.balanceOf(address(staking));
        uint256 ownerBalanceBefore = lockToken.balanceOf(OWNER);

        // Verify exact balance calculations
        assertEq(contractBalance, LOCK_AMOUNT + LOCK_AMOUNT * 2); // USER + USER_2 positions

        vm.prank(OWNER);
        staking.emergencySweep();

        // Verify exact transfer
        assertEq(lockToken.balanceOf(OWNER), ownerBalanceBefore + contractBalance);
        assertEq(lockToken.balanceOf(address(staking)), 0);
    }
}
