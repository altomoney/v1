// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";

contract LiquidationPeriphery_RecoverERC20_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        borrowToken.mint(address(periphery), 100 ether);

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.recoverERC20(address(borrowToken), 100 ether);
    }

    function test_TransferTokensToTreasury_WhenCallerIsOwner() public {
        uint256 amount = 100 ether;
        borrowToken.mint(address(periphery), amount);

        uint256 treasuryBalanceBefore = borrowToken.balanceOf(TREASURY);
        uint256 peripheryBalanceBefore = borrowToken.balanceOf(address(periphery));

        vm.prank(OWNER);
        periphery.recoverERC20(address(borrowToken), amount);

        assertEq(borrowToken.balanceOf(TREASURY), treasuryBalanceBefore + amount);
        assertEq(borrowToken.balanceOf(address(periphery)), peripheryBalanceBefore - amount);
    }

    function test_TransferUnrelatedTokenToTreasury_WhenCallerIsOwner() public {
        ERC20Mock unrelatedToken = new ERC20Mock("Unrelated", "UNR");
        uint256 amount = 100 ether;
        deal(address(unrelatedToken), address(periphery), amount);

        uint256 treasuryBalanceBefore = unrelatedToken.balanceOf(TREASURY);
        uint256 peripheryBalanceBefore = unrelatedToken.balanceOf(address(periphery));

        vm.prank(OWNER);
        periphery.recoverERC20(address(unrelatedToken), amount);

        assertEq(unrelatedToken.balanceOf(TREASURY), treasuryBalanceBefore + amount);
        assertEq(unrelatedToken.balanceOf(address(periphery)), peripheryBalanceBefore - amount);
    }
}
