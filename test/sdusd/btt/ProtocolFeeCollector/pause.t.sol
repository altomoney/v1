// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_Pause_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotConfiguredPauser() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, USER, PAUSE_TYPE));
        collector.pause(PAUSE_TYPE, true);
    }

    function test_NonOwnerPauserCanPauseAndEmitsPaused() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, true);

        vm.prank(PAUSER);
        collector.pause(PAUSE_TYPE, true);

        assertTrue(collector.paused(PAUSE_TYPE));
    }

    function test_RevertWhen_NonOwnerPauserPausesAlreadyPausedType() public {
        _pause();

        vm.prank(PAUSER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, true, true));
        collector.pause(PAUSE_TYPE, true);
    }

    function test_NonOwnerPauserCanUnpauseAndEmitsEvent() public {
        _pause();
        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, false);
        vm.prank(PAUSER);
        collector.pause(PAUSE_TYPE, false);
        assertFalse(collector.paused(PAUSE_TYPE));
    }

    function test_RevertWhen_NonOwnerPauserUnpausesAlreadyUnpausedType() public {
        vm.prank(PAUSER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, false, false));
        collector.pause(PAUSE_TYPE, false);
    }

    function test_OwnerCanPauseAndEmitsPaused() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.Paused(ADMIN, PAUSE_TYPE, true);

        vm.prank(ADMIN);
        collector.pause(PAUSE_TYPE, true);

        assertTrue(collector.paused(PAUSE_TYPE));
    }

    function test_OwnerCanUnpauseAndEmitsPaused() public {
        _pause();

        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.Paused(ADMIN, PAUSE_TYPE, false);

        vm.prank(ADMIN);
        collector.pause(PAUSE_TYPE, false);

        assertFalse(collector.paused(PAUSE_TYPE));
    }

    function test_RevertWhen_OwnerSetsCurrentPauseStateAgain() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, false, false));
        collector.pause(PAUSE_TYPE, false);
    }
}
