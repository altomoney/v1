// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Pause_Test is SDUSDCommon {
    function test_RevertWhen_CallerIsNotConfiguredPauser() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, USER, PAUSE_TYPE));
        vault.pause(PAUSE_TYPE, true);
    }

    function test_RevertWhen_UnconfiguredPauserAttemptsToUnpause() public {
        _pauseVault();
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, USER, PAUSE_TYPE));
        vault.pause(PAUSE_TYPE, false);
    }

    function test_NonOwnerPauserCanPauseAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, true);
        vm.prank(PAUSER);
        vault.pause(PAUSE_TYPE, true);
        assertTrue(vault.paused(PAUSE_TYPE));
    }

    function test_RevertWhen_NonOwnerPauserPausesAlreadyPausedType() public {
        _pauseVault();
        vm.prank(PAUSER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, true, true));
        vault.pause(PAUSE_TYPE, true);
    }

    function test_NonOwnerPauserCanUnpauseAndEmitsEvent() public {
        _pauseVault();
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, false);
        vm.prank(PAUSER);
        vault.pause(PAUSE_TYPE, false);
        assertFalse(vault.paused(PAUSE_TYPE));
    }

    function test_RevertWhen_NonOwnerPauserUnpausesAlreadyUnpausedType() public {
        vm.prank(PAUSER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, false, false));
        vault.pause(PAUSE_TYPE, false);
    }

    function test_OwnerCanPauseAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.Paused(ADMIN, PAUSE_TYPE, true);
        vm.prank(ADMIN);
        vault.pause(PAUSE_TYPE, true);
        assertTrue(vault.paused(PAUSE_TYPE));
    }

    function test_OwnerCanUnpauseAndEmitsEvent() public {
        _pauseVault();
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.Paused(ADMIN, PAUSE_TYPE, false);
        vm.prank(ADMIN);
        vault.pause(PAUSE_TYPE, false);
        assertFalse(vault.paused(PAUSE_TYPE));
    }

    function test_RevertWhen_OwnerSetsCurrentPauseStateAgain() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, false, false));
        vault.pause(PAUSE_TYPE, false);
    }
}
