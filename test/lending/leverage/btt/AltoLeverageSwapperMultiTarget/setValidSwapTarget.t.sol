// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperMultiTargetEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {AltoLeverageSwapperMultiTargetCommon} from "../SwapperCommon.t.sol";

contract AltoLeverageSwapperMultiTargetSetValidSwapTargetTest is AltoLeverageSwapperMultiTargetCommon {
    function test_RevertWhen_CallerIsNotOwner_BeforeAddressValidation() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(address(0), true);
        assertFalse(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(address(0)));
        assertTrue(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(address(target)));
    }

    function test_RevertWhen_TargetIsZero_ForEitherStatus() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(address(0), true);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(address(0), false);
        vm.stopPrank();
        assertFalse(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(address(0)));
    }

    function test_RevertWhen_StatusIsUnchanged_ForFalseAndTrue() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(OTHER, false);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(address(target), true);
        vm.stopPrank();
        assertFalse(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(OTHER));
        assertTrue(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(address(target)));
    }

    function test_WhenStatusChanges_AllowsContractsAndEoasAndEmitsExactEvents() public {
        _setAndAssert(OTHER, true);
        _setAndAssert(OTHER, false);
        _setAndAssert(address(target), false);
        _setAndAssert(address(target), true);
    }

    function test_WhenCallerIsAlreadyWhitelisted_TargetChangesPreserveItsPermission() public {
        _allowCaller();
        assertTrue(swapper.isWhitelisted(CALLER));

        _setAndAssert(OTHER, true);
        _setAndAssert(OTHER, false);
    }

    function _setAndAssert(address swapTarget, bool value) internal {
        bool callerPermissionBefore = swapper.isWhitelisted(CALLER);
        vm.recordLogs();
        vm.prank(OWNER);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(swapTarget, value);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(swapTarget), value);
        assertEq(AltoLeverageSwapperMultiTarget(address(swapper)).owner(), OWNER);
        assertFalse(AltoLeverageSwapperMultiTarget(address(swapper)).isValidSwapTarget(address(0)));
        assertEq(swapper.isWhitelisted(CALLER), callerPermissionBefore, "caller whitelist permission preserved");
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(swapper));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], IAltoLeverageSwapperMultiTargetEvents.SetValidSwapTarget.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(swapTarget))));
        assertEq(logs[0].data, abi.encode(value));
    }
}
