// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {SwapperCommon} from "./SwapperCommon.t.sol";

/// @dev Inherited by both concrete swapper suites; each deploys its own production implementation.
abstract contract SwapperWhitelistTests is SwapperCommon {
    function test_RevertWhen_CallerIsNotOwner_BeforeUnchangedValueCheck() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        swapper.setWhitelisted(CALLER, false);
        assertFalse(swapper.isWhitelisted(CALLER));
    }

    function test_RevertWhen_StatusIsUnchanged_ForFalseAndTrue() public {
        vm.prank(OWNER);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.setWhitelisted(CALLER, false);
        assertFalse(swapper.isWhitelisted(CALLER));

        _allowCaller();
        vm.prank(OWNER);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.setWhitelisted(CALLER, true);
        assertTrue(swapper.isWhitelisted(CALLER));
    }

    function test_WhenStatusChanges_AddsAndRemovesAccountWithExactEvents() public {
        _setAndAssert(CALLER, true);
        _setAndAssert(CALLER, false);
    }

    function test_WhenAccountIsZero_AllowsAddingAndRemovingIt() public {
        _setAndAssert(address(0), true);
        _setAndAssert(address(0), false);
    }

    function test_WhenAnotherAccountIsAlreadyWhitelisted_PreservesItsPermission() public {
        vm.prank(OWNER);
        swapper.setWhitelisted(OTHER, true);
        assertTrue(swapper.isWhitelisted(OTHER));

        _setAndAssert(CALLER, true);
        _setAndAssert(CALLER, false);
    }

    function _setAndAssert(address account, bool value) internal {
        bool otherPermissionBefore = swapper.isWhitelisted(OTHER);
        vm.recordLogs();
        vm.prank(OWNER);
        swapper.setWhitelisted(account, value);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(swapper.isWhitelisted(account), value);
        assertEq(swapper.isWhitelisted(OTHER), otherPermissionBefore, "unrelated whitelist permission preserved");
        assertEq(Ownable(address(swapper)).owner(), OWNER);
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(swapper));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], IAltoLeverageSwapperEvents.SetWhitelisted.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(account))));
        assertEq(logs[0].data, abi.encode(value));
    }
}
