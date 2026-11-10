// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {PAUSE_TYPE, RESCUE_TYPE} from "@alto/utils/Constants.sol";
import {IAltoStakingErrors} from "@alto/staking/interfaces/IAltoStaking.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract AltoStakingRescueModeDisablePrevention is AltoStakingCommon {
    address public constant RESCUE_PAUSER = address(0x6);
    address public constant NORMAL_PAUSER = address(0x7);

    function setUp() public override {
        super.setUp();
        _deployWithThreeContainers();
        _activateAllContainers();
        _startEpoch();

        // Set up pausers
        vm.startPrank(OWNER);
        staking.setPauser(RESCUE_PAUSER, RESCUE_TYPE, true);
        staking.setPauser(NORMAL_PAUSER, PAUSE_TYPE, true);
        vm.stopPrank();
    }

    modifier givenRescueModeIsNotEnabled() {
        // Ensure rescue mode is not enabled
        assertFalse(staking.paused(RESCUE_TYPE));
        _;
    }

    function test_WhenEnablingRescueMode() external givenRescueModeIsNotEnabled {
        // it should enable rescue mode successfully
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(RESCUE_PAUSER, RESCUE_TYPE, true);

        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, true);

        assertTrue(staking.paused(RESCUE_TYPE));
    }

    function test_RevertWhen_DisablingRescueMode() external givenRescueModeIsNotEnabled {
        // it should revert with AltoStakingInvalidInput
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);

        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, false);
    }

    modifier givenRescueModeIsEnabled() {
        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, true);
        assertTrue(staking.paused(RESCUE_TYPE));
        _;
    }

    function test_RevertWhen_AttemptingToDisableRescueMode() external givenRescueModeIsEnabled {
        // it should revert with AltoStakingInvalidInput
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);

        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, false);

        // Verify rescue mode is still enabled
        assertTrue(staking.paused(RESCUE_TYPE));
    }

    function test_RevertWhen_AttemptingToEnableRescueModeAgain() external givenRescueModeIsEnabled {
        // it should revert with StateNotChanged
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, RESCUE_TYPE, true, true));

        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, true);
    }

    function test_RevertWhen_RescueModePauserTriesToDisable() external givenRescueModeIsEnabled {
        // it should revert with AltoStakingInvalidInput
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);

        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, false);

        // Verify rescue mode is still enabled
        assertTrue(staking.paused(RESCUE_TYPE));
    }

    modifier givenNormalPauseModeOperations() {
        _;
    }

    function test_WhenEnablingNormalPause() external givenNormalPauseModeOperations {
        // it should enable normal pause successfully
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(NORMAL_PAUSER, PAUSE_TYPE, true);

        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, true);

        assertTrue(staking.paused(PAUSE_TYPE));
    }

    function test_WhenDisablingNormalPause() external givenNormalPauseModeOperations {
        // First enable normal pause
        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, true);
        assertTrue(staking.paused(PAUSE_TYPE));

        // it should disable normal pause successfully
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(NORMAL_PAUSER, PAUSE_TYPE, false);

        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, false);

        assertFalse(staking.paused(PAUSE_TYPE));
    }

    modifier whenRescueModeIsEnabledAndNormalPauseOperations() {
        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, true);
        assertTrue(staking.paused(RESCUE_TYPE));
        _;
    }

    function test_WhenEnablingNormalPauseWithRescueModeEnabled()
        external
        whenRescueModeIsEnabledAndNormalPauseOperations
    {
        // it should enable normal pause successfully
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(NORMAL_PAUSER, PAUSE_TYPE, true);

        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, true);

        assertTrue(staking.paused(PAUSE_TYPE));
        assertTrue(staking.paused(RESCUE_TYPE)); // Rescue mode should still be enabled
    }

    function test_WhenDisablingNormalPauseWithRescueModeEnabled()
        external
        whenRescueModeIsEnabledAndNormalPauseOperations
    {
        // First enable normal pause
        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, true);
        assertTrue(staking.paused(PAUSE_TYPE));

        // it should disable normal pause successfully
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(NORMAL_PAUSER, PAUSE_TYPE, false);

        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, false);

        assertFalse(staking.paused(PAUSE_TYPE));
        assertTrue(staking.paused(RESCUE_TYPE)); // Rescue mode should still be enabled
    }

    function test_RevertWhen_OwnerTriesToDisableRescueMode() external {
        // Enable rescue mode
        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, true);

        // Owner should not be able to disable rescue mode even if they have pauser rights
        vm.prank(OWNER);
        staking.setPauser(OWNER, RESCUE_TYPE, true);

        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        vm.prank(OWNER);
        staking.pause(RESCUE_TYPE, false);

        // Verify rescue mode is still enabled
        assertTrue(staking.paused(RESCUE_TYPE));
    }

    function test_RevertWhen_DisablingRescueModeAfterOtherOperations() external {
        // Enable rescue mode
        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, true);

        // Perform some other operations
        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, true);

        vm.prank(NORMAL_PAUSER);
        staking.pause(PAUSE_TYPE, false);

        // Try to add a new container
        vm.prank(OWNER);
        staking.addContainer(shortContainer, 0.4 ether);

        // Still should not be able to disable rescue mode
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        vm.prank(RESCUE_PAUSER);
        staking.pause(RESCUE_TYPE, false);

        // Verify rescue mode is still enabled
        assertTrue(staking.paused(RESCUE_TYPE));
    }
}
