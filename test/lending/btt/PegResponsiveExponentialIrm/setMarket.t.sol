// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IRState, IPegResponsiveExponentialIrmEvents} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {
    MockPegResponsiveExponentialIrmMarket
} from "@alto-test/lending/btt/mocks/MockPegResponsiveExponentialIrmMarket.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmSetMarketTest is PegResponsiveExponentialIrmCommon {
    function test_RevertWhen_MarketAlreadySet_ForZeroSameAndDifferentInputs() external {
        _bindMarket();
        IRState memory stateBefore = _readIRState();
        address[] memory suppliedMarkets = new address[](3);
        suppliedMarkets[0] = address(0);
        suppliedMarkets[1] = address(market);
        suppliedMarkets[2] = address(0xD1FF);

        for (uint256 i; i < suppliedMarkets.length; ++i) {
            vm.recordLogs();
            vm.expectRevert(IIrm.IrmMarketAlreadySet.selector);
            irm.setMarket(suppliedMarkets[i]);
            assertEq(vm.getRecordedLogs().length, 0);
            assertEq(irm.market(), address(market));
            _assertIRState(stateBefore);
        }
    }

    function test_RevertWhen_MarketIsUnsetAndSuppliedMarketIsZero() external {
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.expectRevert(IIrm.IrmInvalidParams.selector);
        irm.setMarket(address(0));

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(irm.market(), address(0));
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_TimestampExceedsUint48_RollsBackBinding() external {
        uint256 overflowingTimestamp = uint256(type(uint48).max) + 1;
        vm.warp(overflowingTimestamp);
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(48), overflowingTimestamp)
        );
        irm.setMarket(address(market));

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(irm.market(), address(0));
        _assertIRState(stateBefore);
    }

    function test_AcceptsZeroTimestamp() external {
        vm.warp(0);
        _assertBindingAtCurrentTimestamp(address(market));
    }

    function test_AcceptsMaximumUint48Timestamp() external {
        vm.warp(type(uint48).max);
        _assertBindingAtCurrentTimestamp(address(market));
    }

    function test_FirstBindingIsPermissionlessForOwnerNonOwnerAndMarket() external {
        _assertPermissionlessBinding(OWNER, address(0x1001));
        _assertPermissionlessBinding(NON_OWNER, address(0x1002));
        _assertPermissionlessBinding(address(0x1003), address(0x1003));
    }

    function test_AcceptsEoaWithoutCodeOrInterfaceValidation() external {
        address noCodeMarket = address(0xBEEF);
        assertEq(noCodeMarket.code.length, 0);

        _assertBindingAtCurrentTimestamp(noCodeMarket);
        assertEq(irm.market(), noCodeMarket);
    }

    function test_SetsTimestampPreservesOtherStateAndEmitsOnlyIRStateUpdated() external {
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);
        _mockOracleReturnData(hex"01");
        vm.mockCall(address(market), abi.encodeWithSelector(IPausable.paused.selector, PAUSE_TYPE), hex"01");
        market.setAccrueRevertPoint(MockPegResponsiveExponentialIrmMarket.AccrueRevertPoint.BEFORE_CALLBACK);

        IRState memory expectedState = seededState;
        expectedState.lastUpdate = uint48(block.timestamp);

        vm.recordLogs();
        irm.setMarket(address(market));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(irm.market(), address(market));
        _assertIRState(expectedState);
        assertEq(market.accrueInterestCalls(), 0);
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(irm));
        assertEq(logs[0].topics[0], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(expectedState));

        vm.expectRevert(IIrm.IrmMarketAlreadySet.selector);
        irm.setMarket(address(0xCA11));
    }

    function _assertPermissionlessBinding(address caller, address suppliedMarket) private {
        irm = _deployIrm(irmConfig);
        vm.prank(caller);
        irm.setMarket(suppliedMarket);

        assertEq(irm.market(), suppliedMarket);
        assertEq(_readIRState().lastUpdate, uint48(block.timestamp));
    }

    function _assertBindingAtCurrentTimestamp(address suppliedMarket) private {
        IRState memory expectedState = _readIRState();
        expectedState.lastUpdate = uint48(block.timestamp);

        vm.recordLogs();
        irm.setMarket(suppliedMarket);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(irm));
        assertEq(logs[0].topics[0], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(expectedState));
        _assertIRState(expectedState);
    }
}
