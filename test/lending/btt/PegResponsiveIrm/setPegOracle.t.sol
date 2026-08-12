// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {
    IRState,
    IPegResponsiveIrmErrors,
    IPegResponsiveIrmEvents
} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";
import {MockPegResponsiveIrmMarket} from "@alto-test/lending/btt/mocks/MockPegResponsiveIrmMarket.sol";
import {PegResponsiveIrmCommon} from "./PegResponsiveIrmCommon.t.sol";

contract PegResponsiveIrmSetPegOracleTest is PegResponsiveIrmCommon {
    error MockPausedQueryReverted(uint256 code);

    uint256 private constant PAUSED_REVERT_CODE = 0xA11CE;

    function test_RevertWhen_CallerIsNotOwner_BeforeInputValidationOrCheckpoint() external {
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        irm.setPegOracle(address(0));

        assertEq(address(irm.oracle()), address(oracle));
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_CallerIsPendingOwner() external {
        vm.prank(OWNER);
        irm.transferOwnership(PENDING_OWNER);
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(PENDING_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PENDING_OWNER));
        irm.setPegOracle(address(0));

        assertEq(address(irm.oracle()), address(oracle));
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_NewOracleIsZero_BeforeCheckpoint() external {
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert(IPegResponsiveIrmErrors.PegResponsiveIrmInvalidOracle.selector);
        irm.setPegOracle(address(0));

        assertEq(address(irm.oracle()), address(oracle));
        _assertIRState(stateBefore);
    }

    function test_WhenMarketIsUnset_SkipsCheckpointAndEmitsOnlySetterEvent() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        _mockOracleReturnData(hex"01");
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        _setPegOracleAsOwner(address(newOracle));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(address(irm.oracle()), address(newOracle));
        _assertIRState(stateBefore);
        assertEq(logs.length, 1);
        _assertSetPegOracleEvent(logs[0], address(oracle), address(newOracle));
    }

    function test_WhenMarketIsPaused_QueriesExactPauseTypeAndSkipsAccrual() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        _bindMarket();
        market.setPaused(PAUSE_TYPE, true);
        vm.expectCall(address(market), _pausedCall(), 1);

        _setPegOracleAsOwner(address(newOracle));

        assertEq(address(irm.oracle()), address(newOracle));
        assertEq(market.accrueInterestCalls(), 0);
    }

    function test_RevertWhen_PausedQueryReverts_BubblesAndRollsBack() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert(_pausedQueryRevertData());
        irm.setPegOracle(address(newOracle));

        assertEq(address(irm.oracle()), address(oracle));
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_PausedReturnDataIsMalformed_RollsBack() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        _bindMarket();
        vm.mockCall(address(market), _pausedCall(), hex"01");
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert();
        irm.setPegOracle(address(newOracle));

        assertEq(address(irm.oracle()), address(oracle));
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_AccrualRevertsAfterCallback_RollsBackNestedState() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        _bindMarket();
        vm.warp(DEFAULT_NOW + 1);
        _setCurrentObservation(STRESS_PRICE);
        market.setAccrueRevertPoint(MockPegResponsiveIrmMarket.AccrueRevertPoint.AFTER_CALLBACK);
        IRState memory stateBefore = _readIRState();
        vm.expectCall(address(market), _pausedCall(), 1);
        vm.expectCall(address(market), abi.encodeWithSelector(IMarketBase.accrueInterest.selector), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockPegResponsiveIrmMarket.MockPegResponsiveIrmMarketAccrueReverted.selector,
                MockPegResponsiveIrmMarket.AccrueRevertPoint.AFTER_CALLBACK
            )
        );
        irm.setPegOracle(address(newOracle));

        assertEq(address(irm.oracle()), address(oracle));
        _assertIRState(stateBefore);
    }

    function test_WhenAccrualCallbacks_UsesOldOracleAndRetainsPostCheckpointStateExceptRecovery() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        newOracle.setGetPriceReverts(true);
        _bindMarket();
        uint48 recoveryStartedAt = uint48(block.timestamp - 10);
        IRState memory seededState = IRState({
            borrowRate: irmConfig.baseRate,
            lastUpdate: uint48(block.timestamp - 100),
            recoveryStartedAt: recoveryStartedAt,
            stressMode: true
        });
        _setIRState(seededState);
        _setCurrentObservation(RECOVERY_PRICE);
        vm.expectCall(address(market), _pausedCall(), 1);
        vm.expectCall(address(market), abi.encodeWithSelector(IMarketBase.accrueInterest.selector), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.recordLogs();
        _setPegOracleAsOwner(address(newOracle));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory checkpointState = IRState({
            borrowRate: irmConfig.stressRate,
            lastUpdate: uint48(block.timestamp),
            recoveryStartedAt: recoveryStartedAt,
            stressMode: true
        });
        IRState memory finalState = IRState({
            borrowRate: checkpointState.borrowRate,
            lastUpdate: checkpointState.lastUpdate,
            recoveryStartedAt: 0,
            stressMode: checkpointState.stressMode
        });

        assertEq(address(irm.oracle()), address(newOracle));
        assertEq(market.accrueInterestCalls(), 1);
        assertEq(market.lastBorrowRate(), seededState.borrowRate);
        assertEq(market.lastInterest(), 0);
        _assertIRState(finalState);

        assertEq(logs.length, 5);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.BorrowRateUpdated.selector);
        assertEq(
            logs[0].data,
            abi.encode(
                seededState.borrowRate, checkpointState.borrowRate, RECOVERY_PRICE, uint48(block.timestamp), true
            )
        );
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(checkpointState));
        _assertSetPegOracleEvent(logs[2], address(oracle), address(newOracle));
        _assertIrmEvent(logs[3], IPegResponsiveIrmEvents.StressStateUpdated.selector);
        assertEq(logs[3].data, abi.encode(true, uint48(0), uint256(0)));
        _assertIrmEvent(logs[4], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[4].data, abi.encode(finalState));
    }

    function test_WhenNewOracleEqualsCurrent_StillCheckpointsAndEmitsSameAddress() external {
        _bindMarket();
        vm.expectCall(address(market), abi.encodeWithSelector(IMarketBase.accrueInterest.selector), 1);

        vm.recordLogs();
        _setPegOracleAsOwner(address(oracle));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(address(irm.oracle()), address(oracle));
        assertEq(market.accrueInterestCalls(), 1);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.BorrowRateUpdated.selector);
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        _assertSetPegOracleEvent(logs[2], address(oracle), address(oracle));
    }

    function test_AcceptsOracleWithoutCodeAndDoesNotSampleIt() external {
        address noCodeOracle = address(0xBEEF);
        assertEq(noCodeOracle.code.length, 0);
        _mockOracleReturnData(hex"01");

        _setPegOracleAsOwner(noCodeOracle);

        assertEq(address(irm.oracle()), noCodeOracle);
        vm.expectRevert();
        irm.previewBorrowRate();
    }

    function test_WhenRecoveryIsActive_ClearsOnlyRecoveryInExactEventOrder() external {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);

        vm.recordLogs();
        _setPegOracleAsOwner(address(newOracle));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = seededState;
        expectedState.recoveryStartedAt = 0;
        _assertIRState(expectedState);
        assertEq(logs.length, 3);
        _assertSetPegOracleEvent(logs[0], address(oracle), address(newOracle));
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.StressStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(true, uint48(0), uint256(0)));
        _assertIrmEvent(logs[2], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[2].data, abi.encode(expectedState));
    }

    function _setPegOracleAsOwner(address newOracle) private {
        vm.prank(OWNER);
        irm.setPegOracle(newOracle);
    }

    function _pausedCall() private pure returns (bytes memory) {
        return abi.encodeWithSelector(IPausable.paused.selector, PAUSE_TYPE);
    }

    function _mockPausedQueryRevert() private {
        vm.mockCallRevert(address(market), _pausedCall(), _pausedQueryRevertData());
    }

    function _pausedQueryRevertData() private pure returns (bytes memory) {
        return abi.encodeWithSelector(MockPausedQueryReverted.selector, PAUSED_REVERT_CODE);
    }

    function _assertSetPegOracleEvent(Vm.Log memory log, address oldOracle, address newOracle) private view {
        _assertIrmEvent(log, IPegResponsiveIrmEvents.SetPegOracle.selector);
        assertEq(log.topics.length, 3);
        assertEq(log.topics[1], bytes32(uint256(uint160(oldOracle))));
        assertEq(log.topics[2], bytes32(uint256(uint160(newOracle))));
    }

    function _assertIrmEvent(Vm.Log memory log, bytes32 selector) private view {
        assertEq(log.emitter, address(irm));
        assertEq(log.topics[0], selector);
    }
}
