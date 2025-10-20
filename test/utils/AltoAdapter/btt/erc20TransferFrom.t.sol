// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdapterCommonSetup} from "../AdapterCommonSetup.t.sol";
import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {Call} from "@morpho-org/bundler3/Bundler3.sol";

contract Erc20TransferFromTest is AdapterCommonSetup {
    function setUp() public override {
        super.setUp();

        // Give USER tokens and approve adapter
        deal(address(borrowToken), USER, 100e18);
        vm.prank(USER);
        borrowToken.approve(address(altoAdapter), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        vm.startPrank(USER);

        bundle.push(_erc20TransferFrom(address(borrowToken), address(0), 1e18));

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_AmountMaxAndInitiatorHasZeroBalance() public {
        vm.startPrank(RECEIVER); // RECEIVER has no tokens

        bundle.push(_erc20TransferFrom(address(borrowToken), USER, type(uint256).max));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_AmountIsZero() public {
        vm.startPrank(USER);

        bundle.push(_erc20TransferFrom(address(borrowToken), RECEIVER, 0));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Erc20TransferFrom_WithSpecifiedAmount() public {
        vm.startPrank(USER);

        uint256 amount = 10e18;
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_erc20TransferFrom(address(borrowToken), RECEIVER, amount));
        bundler3.multicall(bundle);

        uint256 userBalanceAfter = borrowToken.balanceOf(USER);
        uint256 receiverBalanceAfter = borrowToken.balanceOf(RECEIVER);

        assertEq(userBalanceAfter, userBalanceBefore - amount);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + amount);

        vm.stopPrank();
    }

    function test_Erc20TransferFrom_WithMaxAmount() public {
        vm.startPrank(USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_erc20TransferFrom(address(borrowToken), RECEIVER, type(uint256).max));
        bundler3.multicall(bundle);

        uint256 userBalanceAfter = borrowToken.balanceOf(USER);
        uint256 receiverBalanceAfter = borrowToken.balanceOf(RECEIVER);

        assertEq(userBalanceAfter, 0);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + userBalanceBefore);

        vm.stopPrank();
    }

    function testFuzz_Erc20TransferFrom_WithVariousAmounts(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1, 50e18);

        vm.startPrank(USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_erc20TransferFrom(address(borrowToken), RECEIVER, amount));
        bundler3.multicall(bundle);

        uint256 userBalanceAfter = borrowToken.balanceOf(USER);
        uint256 receiverBalanceAfter = borrowToken.balanceOf(RECEIVER);

        assertEq(userBalanceAfter, userBalanceBefore - amount);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + amount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    //////////////////////////////////////////////////////////////*/

    function _erc20TransferFrom(address token, address receiver, uint256 amount)
        internal
        view
        override
        returns (Call memory)
    {
        return _call(altoAdapter, abi.encodeCall(altoAdapter.erc20TransferFrom, (token, receiver, amount)));
    }
}
