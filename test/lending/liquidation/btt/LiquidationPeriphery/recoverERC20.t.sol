// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";

contract LiquidationPeriphery_RecoverERC20_Test is LiquidationPeripheryCommon {
    address internal immutable RECIPIENT = makeAddr("Recipient");

    function test_RevertWhen_CallerIsNotOwner() public {
        borrowToken.mint(address(periphery), 100 ether);

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.recoverERC20(address(borrowToken), 100 ether, RECIPIENT);
    }

    function test_TransferTokensToRecipient_WhenCallerIsOwner() public {
        uint256 amount = 100 ether;
        borrowToken.mint(address(periphery), amount);

        uint256 recipientBalanceBefore = borrowToken.balanceOf(RECIPIENT);
        uint256 peripheryBalanceBefore = borrowToken.balanceOf(address(periphery));

        vm.prank(OWNER);
        periphery.recoverERC20(address(borrowToken), amount, RECIPIENT);

        assertEq(borrowToken.balanceOf(RECIPIENT), recipientBalanceBefore + amount);
        assertEq(borrowToken.balanceOf(address(periphery)), peripheryBalanceBefore - amount);
    }

    function test_TransferUnrelatedTokenToRecipient_WhenCallerIsOwner() public {
        ERC20Mock unrelatedToken = new ERC20Mock("Unrelated", "UNR");
        uint256 amount = 100 ether;
        deal(address(unrelatedToken), address(periphery), amount);

        uint256 recipientBalanceBefore = unrelatedToken.balanceOf(RECIPIENT);
        uint256 peripheryBalanceBefore = unrelatedToken.balanceOf(address(periphery));

        vm.prank(OWNER);
        periphery.recoverERC20(address(unrelatedToken), amount, RECIPIENT);

        assertEq(unrelatedToken.balanceOf(RECIPIENT), recipientBalanceBefore + amount);
        assertEq(unrelatedToken.balanceOf(address(periphery)), peripheryBalanceBefore - amount);
    }
}
