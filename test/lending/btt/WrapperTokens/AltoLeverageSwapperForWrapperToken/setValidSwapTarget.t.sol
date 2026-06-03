// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoLeverageSwapperForWrapperTokenCommon} from "./AltoLeverageSwapperForWrapperTokenCommon.t.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperMultiTargetEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SwapTargetMock} from "../WrapperToken/mocks/SwapTargetMock.sol";

contract SetValidSwapTargetTest is AltoLeverageSwapperForWrapperTokenCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        swapper.setValidSwapTarget(makeAddr("swapTarget"), true);
    }

    function test_RevertWhen_SwapTargetIsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.setValidSwapTarget(address(0), true);
    }

    function test_RevertWhen_IsValidStatusIsUnchanged() public {
        assertTrue(swapper.isValidSwapTarget(address(swapTarget)));

        vm.prank(owner);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.setValidSwapTarget(address(swapTarget), true);
    }

    function test_SetValidSwapTarget_WhenSettingToTrue() public {
        SwapTargetMock newSwapTarget = new SwapTargetMock();
        assertFalse(swapper.isValidSwapTarget(address(newSwapTarget)));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.SetValidSwapTarget(address(newSwapTarget), true);
        swapper.setValidSwapTarget(address(newSwapTarget), true);

        assertTrue(swapper.isValidSwapTarget(address(newSwapTarget)));
    }

    function test_SetValidSwapTarget_WhenSettingToFalse() public {
        assertTrue(swapper.isValidSwapTarget(address(swapTarget)));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.SetValidSwapTarget(address(swapTarget), false);
        swapper.setValidSwapTarget(address(swapTarget), false);

        assertFalse(swapper.isValidSwapTarget(address(swapTarget)));
    }
}
