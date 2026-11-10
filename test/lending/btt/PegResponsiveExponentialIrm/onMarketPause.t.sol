// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IRState, IPegResponsiveExponentialIrmEvents} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmOnMarketPauseTest is PegResponsiveExponentialIrmCommon {
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

    function test_WhenPausing_ItCheckpointsThroughMarketBeforeSettingPause() external {
        _bindMarket();
        _setCurrentObservation(STRESS_PRICE);
        _setIRState(BASE_RATE, uint48(block.timestamp - 10), 0, false);
        IRState memory expectedState = IRState({
            borrowRate: STRESS_RATE, lastUpdate: uint48(block.timestamp), recoveryStartedAt: 0, stressMode: true
        });

        _pauseMarket();

        assertTrue(market.paused(PAUSE_TYPE), "market paused");
        _assertIRState(expectedState);
    }

    function test_RevertWhen_UnpausingAtTimestampAboveUint48_PreservesRecovery() external {
        _bindMarket();
        _pauseMarket();
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);
        uint256 overflowingTimestamp = uint256(type(uint48).max) + 1;
        vm.warp(overflowingTimestamp);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(48), overflowingTimestamp)
        );
        _unpauseMarket();

        assertEq(vm.getRecordedLogs().length, 0);
        _assertIRState(seededState);
    }

    function test_WhenUnpausing_AcceptsZeroTimestamp() external {
        _bindMarket();
        _pauseMarket();
        vm.warp(0);

        IRState memory expectedState = _readIRState();
        expectedState.lastUpdate = 0;
        _assertUnpauseWithNoRecovery(expectedState);
    }

    function test_WhenUnpausing_AcceptsMaximumUint48Timestamp() external {
        _bindMarket();
        _pauseMarket();
        vm.warp(type(uint48).max);

        IRState memory expectedState = _readIRState();
        expectedState.lastUpdate = type(uint48).max;
        _assertUnpauseWithNoRecovery(expectedState);
    }

    function test_WhenRecoveryIsInactive_UpdatesOnlyTimestampAndEmitsOnlyState() external {
        _bindMarket();
        _pauseMarket();
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
        _pauseMarket();
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
        _unpauseMarket();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertIRState(expectedState);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.StressStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(stressMode, uint48(0), uint256(0)));
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
    }

    function _assertUnpauseWithNoRecovery(IRState memory expectedState) private {
        vm.recordLogs();
        _unpauseMarket();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertIRState(expectedState);
        assertEq(logs.length, 2);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(expectedState));
    }

    function _assertIrmEvent(Vm.Log memory log, bytes32 selector) private view {
        assertEq(log.emitter, address(irm));
        assertEq(log.topics[0], selector);
    }
}
