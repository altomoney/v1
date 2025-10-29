// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

contract DUSDSetFlashFeeReceiver is DUSDCommon {
    modifier givenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setFlashFeeReceiver(FLASH_FEE_RECEIVER);
    }

    function test_WhenSettingFlashFeeReceiverToZeroAddress() external givenCallerIsOwner {
        // First set a non-zero receiver
        vm.prank(OWNER);
        dusd.setFlashFeeReceiver(FLASH_FEE_RECEIVER);
        assertEq(dusd.flashFeeReceiver(), FLASH_FEE_RECEIVER);

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFeeReceiver(FLASH_FEE_RECEIVER, address(0));

        vm.prank(OWNER);
        dusd.setFlashFeeReceiver(address(0));

        // it should set flashFeeReceiver to zero address
        assertEq(dusd.flashFeeReceiver(), address(0));
    }

    function test_WhenSettingFlashFeeReceiverToValidAddress() external givenCallerIsOwner {
        address oldReceiver = dusd.flashFeeReceiver();

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFeeReceiver(oldReceiver, FLASH_FEE_RECEIVER);

        vm.prank(OWNER);
        dusd.setFlashFeeReceiver(FLASH_FEE_RECEIVER);

        // it should set flashFeeReceiver to the new address
        assertEq(dusd.flashFeeReceiver(), FLASH_FEE_RECEIVER);
    }

    function test_WhenSettingFlashFeeReceiverToSameAddress() external givenCallerIsOwner {
        // First set the receiver
        vm.prank(OWNER);
        dusd.setFlashFeeReceiver(FLASH_FEE_RECEIVER);
        assertEq(dusd.flashFeeReceiver(), FLASH_FEE_RECEIVER);

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFeeReceiver(FLASH_FEE_RECEIVER, FLASH_FEE_RECEIVER);

        vm.prank(OWNER);
        dusd.setFlashFeeReceiver(FLASH_FEE_RECEIVER);

        // it should update flashFeeReceiver to the same address
        assertEq(dusd.flashFeeReceiver(), FLASH_FEE_RECEIVER);
    }
}
