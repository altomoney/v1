// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IDusdPegOracleCurveEvents} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";
import {DusdPegOracleCurveCommon} from "./DusdPegOracleCurveCommon.t.sol";

contract DusdPegOracleCurveSetRuntimeChecksTest is DusdPegOracleCurveCommon {
    function setUp() public override {
        super.setUp();
        oracle = _deployOracle(false);
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.recordLogs();
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.setRuntimeChecks(true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(oracle.runtimeConfigChecksEnabled());
        assertEq(logs.length, 0);
    }

    function test_RevertWhen_CallerIsPendingOwner() external {
        vm.prank(OWNER);
        oracle.transferOwnership(PENDING_OWNER);

        vm.recordLogs();
        vm.prank(PENDING_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PENDING_OWNER));
        oracle.setRuntimeChecks(true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(oracle.runtimeConfigChecksEnabled());
        assertEq(logs.length, 0);
    }

    function test_WhenOwnerEnablesDisabledRuntimeChecks() external {
        _assertRuntimeUpdate(false, true);
    }

    function test_WhenOwnerDisablesEnabledRuntimeChecks() external {
        _assertRuntimeUpdate(true, false);
    }

    function test_WhenOwnerSetsRuntimeChecksToStoredTrueValue() external {
        _assertRuntimeUpdate(true, true);
    }

    function test_WhenOwnerSetsRuntimeChecksToStoredFalseValue() external {
        _assertRuntimeUpdate(false, false);
    }

    function _assertRuntimeUpdate(bool initialValue, bool enabled) private {
        if (oracle.runtimeConfigChecksEnabled() != initialValue) {
            vm.prank(OWNER);
            oracle.setRuntimeChecks(initialValue);
        }

        vm.expectEmit(false, false, false, true, address(oracle));
        emit IDusdPegOracleCurveEvents.SetRuntimeChecks(enabled);

        vm.prank(OWNER);
        oracle.setRuntimeChecks(enabled);
        assertEq(oracle.runtimeConfigChecksEnabled(), enabled);
    }
}
