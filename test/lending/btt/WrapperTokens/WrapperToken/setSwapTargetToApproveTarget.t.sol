// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {
    IWrapperTokenErrors,
    IWrapperTokenEvents,
    SwapTargetMetadata
} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

contract SetSwapTargetToApproveTargetTest is WrapperTokenCommon {
    address internal swapTarget = makeAddr("swapTarget");
    address internal approveTarget = makeAddr("approveTarget");

    function test_RevertWhen_CallerIsNotOwner() public {
        SwapTargetMetadata memory metadata = SwapTargetMetadata({approveTarget: approveTarget, isValid: true});

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        wrapper.setSwapTargetToApproveTarget(swapTarget, metadata);
    }

    function test_SetSwapTargetToApproveTarget_WhenIsValidIsTrue() public {
        SwapTargetMetadata memory metadata = SwapTargetMetadata({approveTarget: approveTarget, isValid: true});

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.SetSwapTargetToApproveTarget(swapTarget, approveTarget, true);
        wrapper.setSwapTargetToApproveTarget(swapTarget, metadata);

        (address storedApproveTarget, bool isValid) = wrapper.swapTargetToApproveTarget(swapTarget);
        assertEq(storedApproveTarget, approveTarget);
        assertTrue(isValid);
    }

    function test_SetSwapTargetToApproveTarget_WhenIsValidIsFalse() public {
        SwapTargetMetadata memory setMetadata = SwapTargetMetadata({approveTarget: approveTarget, isValid: true});
        vm.prank(owner);
        wrapper.setSwapTargetToApproveTarget(swapTarget, setMetadata);

        SwapTargetMetadata memory deleteMetadata = SwapTargetMetadata({approveTarget: approveTarget, isValid: false});

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.SetSwapTargetToApproveTarget(swapTarget, address(0), false);
        wrapper.setSwapTargetToApproveTarget(swapTarget, deleteMetadata);

        (address storedApproveTarget, bool isValid) = wrapper.swapTargetToApproveTarget(swapTarget);
        assertEq(storedApproveTarget, address(0));
        assertFalse(isValid);
    }
}
