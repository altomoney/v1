// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionFactoryCommon} from "./PositionFactoryCommon.t.sol";
import {IPositionFactoryErrors, IPositionFactoryEvents} from "@alto/positions/interfaces/IPositionFactory.sol";

contract PositionFactory_SetApprovedSwapTarget_Test is PositionFactoryCommon {
    address internal immutable SWAP_TARGET = makeAddr("SwapTarget");

    function test_RevertWhen_CallerIsNotOwner() public {
        _expectOwnableUnauthorized(NON_OWNER);
        factory.setApprovedSwapTarget(SWAP_TARGET, true);
    }

    function test_RevertWhen_SwapTargetIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryZeroAddress.selector);
        factory.setApprovedSwapTarget(address(0), true);
    }

    function test_ReturnsWithoutUpdatingWhenApprovalStatusUnchanged() public {
        vm.startPrank(OWNER);
        factory.setApprovedSwapTarget(SWAP_TARGET, true);

        vm.recordLogs();
        factory.setApprovedSwapTarget(SWAP_TARGET, true);
        vm.stopPrank();

        assertTrue(factory.approvedSwapTarget(SWAP_TARGET));
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_SetApprovedSwapTarget_WhenApprovalStatusChanges() public {
        vm.expectEmit(true, false, false, true);
        emit IPositionFactoryEvents.ApprovedSwapTargetSet(SWAP_TARGET, true);

        vm.prank(OWNER);
        factory.setApprovedSwapTarget(SWAP_TARGET, true);

        assertTrue(factory.approvedSwapTarget(SWAP_TARGET));
    }
}
