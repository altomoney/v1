// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IRState, IPegResponsiveIrmEvents} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PegResponsiveIrmCommon} from "./PegResponsiveIrmCommon.t.sol";

contract PegResponsiveIrmOnMarketPauseTest is PegResponsiveIrmCommon {
    function test_RevertWhen_MarketIsUnset_ForOwnerPendingOwnerAndOtherCaller() external {
        vm.prank(OWNER);
        irm.transferOwnership(PENDING_OWNER);
        IRState memory stateBefore = _readIRState();
        address[] memory callers = new address[](3);
        callers[0] = OWNER;
        callers[1] = PENDING_OWNER;
        callers[2] = NON_OWNER;

        for (uint256 i; i < callers.length; ++i) {
            vm.recordLogs();
            vm.prank(callers[i]);
            vm.expectRevert(IIrm.IrmUnauthorized.selector);
            irm.onMarketPause(false);

            assertEq(vm.getRecordedLogs().length, 0);
            _assertIRState(stateBefore);
        }
    }

    function test_RevertWhen_CallerIsNotBoundMarket() external {
        _bindMarket();
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.prank(NON_OWNER);
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irm.onMarketPause(true);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_UnauthorizedBeforeInspectingFlagOrCastingTimestamp() external {
        _bindMarket();
        uint256 overflowingTimestamp = uint256(type(uint48).max) + 1;
        vm.warp(overflowingTimestamp);
        IRState memory stateBefore = _readIRState();

        vm.prank(NON_OWNER);
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irm.onMarketPause(false);

        _assertIRState(stateBefore);
    }

    function test_WhenPausedIsTrue_AtOverflowingTimestamp_DoesNothing() external {
        _bindMarket();
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);
        _mockOracleReturnData(hex"01");
        market.setPaused(PAUSE_TYPE, false);
        vm.warp(uint256(type(uint48).max) + 1);
        vm.mockCall(address(market), abi.encodeWithSelector(IPausable.paused.selector, PAUSE_TYPE), hex"01");

        vm.recordLogs();
        market.callOnMarketPause(true);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertIRState(seededState);
    }

    function test_RevertWhen_UnpausingAtTimestampAboveUint48_PreservesRecovery() external {
        _bindMarket();
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);
        uint256 overflowingTimestamp = uint256(type(uint48).max) + 1;
        vm.warp(overflowingTimestamp);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(48), overflowingTimestamp)
        );
        market.callOnMarketPause(false);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertIRState(seededState);
    }

    function test_WhenUnpausing_AcceptsZeroTimestamp() external {
        _bindMarket();
        vm.warp(0);

        IRState memory expectedState = _readIRState();
        expectedState.lastUpdate = 0;
        _assertUnpauseWithNoRecovery(expectedState);
    }

    function test_WhenUnpausing_AcceptsMaximumUint48Timestamp() external {
        _bindMarket();
        vm.warp(type(uint48).max);

        IRState memory expectedState = _readIRState();
        expectedState.lastUpdate = type(uint48).max;
        _assertUnpauseWithNoRecovery(expectedState);
    }

    function test_WhenRecoveryIsInactive_UpdatesOnlyTimestampAndEmitsOnlyState() external {
        _bindMarket();
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 0, stressMode: true});
        _setIRState(seededState);
        _mockOracleReturnData(hex"01");
        vm.warp(DEFAULT_NOW + 1 days);

        IRState memory expectedState = seededState;
        expectedState.lastUpdate = uint48(block.timestamp);
        _assertUnpauseWithNoRecovery(expectedState);
    }

    function testFuzz_WhenRecoveryIsActive_ClearsOnlyRecoveryAndEmitsOrderedStateEvents(bool stressMode) external {
        _bindMarket();
        IRState memory seededState = IRState({
            borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: stressMode
        });
        _setIRState(seededState);
        _mockOracleReturnData(hex"01");
        vm.warp(DEFAULT_NOW + 1 days);

        IRState memory expectedState = seededState;
        expectedState.lastUpdate = uint48(block.timestamp);
        expectedState.recoveryStartedAt = 0;

        vm.recordLogs();
        market.callOnMarketPause(false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertIRState(expectedState);
        assertEq(logs.length, 2);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.StressStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(stressMode, uint48(0), uint256(0)));
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
    }

    function _assertUnpauseWithNoRecovery(IRState memory expectedState) private {
        vm.recordLogs();
        market.callOnMarketPause(false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertIRState(expectedState);
        assertEq(logs.length, 1);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(expectedState));
    }

    function _assertIrmEvent(Vm.Log memory log, bytes32 selector) private view {
        assertEq(log.emitter, address(irm));
        assertEq(log.topics[0], selector);
    }
}
