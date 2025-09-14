// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdapterCommonSetup} from "../AdapterCommonSetup.t.sol";
import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Call} from "@morpho-org/bundler3/Bundler3.sol";

contract WrapNativeTest is AdapterCommonSetup {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_AmountMaxAndAdapterHasZeroNativeBalance() public {
        vm.startPrank(USER);

        // Ensure adapter has zero native balance
        assertEq(address(altoAdapter).balance, 0);

        bundle.push(_wrapNative(type(uint256).max, USER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_AmountIsZero() public {
        vm.startPrank(USER);

        bundle.push(_wrapNative(0, USER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WrapNative_WithSpecifiedAmountAndAdapterReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 1 ether;

        // Fund the adapter with native tokens
        vm.deal(address(altoAdapter), amount);

        uint256 adapterNativeBalanceBefore = address(altoAdapter).balance;
        uint256 adapterWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));

        bundle.push(_wrapNative(amount, address(altoAdapter)));
        bundler3.multicall(bundle);

        uint256 adapterNativeBalanceAfter = address(altoAdapter).balance;
        uint256 adapterWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));

        assertEq(adapterNativeBalanceAfter, adapterNativeBalanceBefore - amount);
        assertEq(adapterWrappedBalanceAfter, adapterWrappedBalanceBefore + amount);

        vm.stopPrank();
    }

    function test_WrapNative_WithSpecifiedAmountAndExternalReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 1 ether;

        // Fund the adapter with native tokens
        vm.deal(address(altoAdapter), amount);

        uint256 adapterNativeBalanceBefore = address(altoAdapter).balance;
        uint256 receiverWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(RECEIVER);

        bundle.push(_wrapNative(amount, RECEIVER));
        bundler3.multicall(bundle);

        uint256 adapterNativeBalanceAfter = address(altoAdapter).balance;
        uint256 receiverWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(RECEIVER);

        assertEq(adapterNativeBalanceAfter, adapterNativeBalanceBefore - amount);
        assertEq(receiverWrappedBalanceAfter, receiverWrappedBalanceBefore + amount);

        vm.stopPrank();
    }

    function test_WrapNative_WithMaxAmountAndAdapterReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 2 ether;

        // Fund the adapter with native tokens
        vm.deal(address(altoAdapter), amount);

        uint256 adapterNativeBalanceBefore = address(altoAdapter).balance;
        uint256 adapterWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));

        bundle.push(_wrapNative(type(uint256).max, address(altoAdapter)));
        bundler3.multicall(bundle);

        uint256 adapterNativeBalanceAfter = address(altoAdapter).balance;
        uint256 adapterWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));

        assertEq(adapterNativeBalanceAfter, 0);
        assertEq(adapterWrappedBalanceAfter, adapterWrappedBalanceBefore + amount);

        vm.stopPrank();
    }

    function test_WrapNative_WithMaxAmountAndExternalReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 2 ether;

        // Fund the adapter with native tokens
        vm.deal(address(altoAdapter), amount);

        uint256 adapterNativeBalanceBefore = address(altoAdapter).balance;
        uint256 receiverWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(RECEIVER);

        bundle.push(_wrapNative(type(uint256).max, RECEIVER));
        bundler3.multicall(bundle);

        uint256 adapterNativeBalanceAfter = address(altoAdapter).balance;
        uint256 receiverWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(RECEIVER);

        assertEq(adapterNativeBalanceAfter, 0);
        assertEq(receiverWrappedBalanceAfter, receiverWrappedBalanceBefore + amount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    //////////////////////////////////////////////////////////////*/

    function _wrapNative(uint256 amount, address receiver) internal view returns (Call memory) {
        return _call(altoAdapter, abi.encodeCall(altoAdapter.wrapNative, (amount, receiver)));
    }
}
