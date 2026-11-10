// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {FixedRateIrmCommon} from "./FixedRateIrmCommon.t.sol";

contract FixedRateIrmConstructorTest is FixedRateIrmCommon {
    function test_RevertWhen_OwnerIsZero_BeforeParameterValidation() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new FixedRateIrm(MAX_RATE + 1, address(0));
    }

    function testFuzz_RevertWhen_RateExceedsMaximum(uint256 rate) public {
        rate = bound(rate, MAX_RATE + 1, type(uint256).max);
        vm.expectRevert(IIrm.IrmInvalidParams.selector);
        new FixedRateIrm(rate, OWNER);
    }

    function testFuzz_WhenRateIsValid_StoresRateAndEmitsInitialState(uint256 rate) public {
        _deployAndAssert(bound(rate, 0, MAX_RATE));
    }

    function test_WhenRateIsZeroOrMaximum_AcceptsInclusiveBoundaries() public {
        _deployAndAssert(0);
        _deployAndAssert(MAX_RATE);
    }

    function _deployAndAssert(uint256 candidate) internal {
        vm.recordLogs();
        irm = new FixedRateIrm(candidate, OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(irm.owner(), OWNER);
        assertEq(irm.pendingOwner(), address(0));
        assertEq(irm.market(), address(0));
        _assertState(candidate, 0);

        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(irm));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], Ownable.OwnershipTransferred.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data.length, 0);
        _assertStateLog(logs[1], candidate, 0);
    }
}
