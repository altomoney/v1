// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {ILiquidationPeripheryErrors} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_OnLiquidateCallback_Test is LiquidationPeripheryCommon {
    function _assertBorrowTokenApprovedToMarket(IMarket target, uint256 repayAmount) internal view {
        assertEq(borrowToken.allowance(address(periphery), address(target)), repayAmount);
        assertEq(borrowToken.balanceOf(address(periphery)), repayAmount);
    }

    function test_RevertWhen_CallerIsNotRegisteredMarket() public {
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(borrowMarket));

        vm.prank(makeAddr("RandomCaller"));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_RevertWhen_MarketInCallbackDataDoesNotMatchCaller() public {
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(mintMarket));

        vm.prank(address(borrowMarket));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_TransfersCollateralToLiquidator() public {
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(borrowMarket));

        _fundLiquidatorForDirectRepay();

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(1 ether, collateralAmount, callbackData);

        assertEq(collateralToken.balanceOf(LIQUIDATOR), collateralAmount);
    }

    function test_WhenRepayViaUsmIsFalse_PullsBorrowTokenAndApprovesMarket() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(borrowMarket));

        _fundLiquidatorForDirectRepay();

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(repayAmount, collateralAmount, callbackData);

        assertEq(borrowToken.balanceOf(address(periphery)), repayAmount);
        assertEq(borrowToken.allowance(address(periphery), address(borrowMarket)), repayAmount);
        assertEq(borrowToken.balanceOf(LIQUIDATOR), 100 ether - repayAmount);
        assertEq(collateralToken.balanceOf(LIQUIDATOR), collateralAmount);
    }

    function test_WhenRepayViaUsmIsTrue_AndStableBoughtEqualsBorrowAmount() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);

        _configureUsmOneToOne();
        _fundLiquidatorForUsmRepay(repayAmount);

        bytes memory callbackData = _callbackData(LIQUIDATOR, true, address(borrowMarket));

        uint256 stableBefore = borrowToken.balanceOf(LIQUIDATOR);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(repayAmount, collateralAmount, callbackData);

        assertEq(borrowToken.balanceOf(LIQUIDATOR), stableBefore, "no stable refund when USM sells 1:1");
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
        assertEq(collateralToken.balanceOf(LIQUIDATOR), collateralAmount);
    }

    function test_WhenRepayViaUsmIsTrue_AndStableBoughtExceedsBorrowAmount_RefundsLiquidator() public {
        uint256 repayAmount = 1 ether;
        deal(address(collateralToken), address(periphery), repayAmount);

        _configureUsmExcessSell();
        _fundLiquidatorForUsmRepay(repayAmount);

        bytes memory callbackData = _callbackData(LIQUIDATOR, true, address(borrowMarket));

        uint256 stableBefore = borrowToken.balanceOf(LIQUIDATOR);
        uint256 expectedRefund = _expectedStableRefund(repayAmount);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(repayAmount, repayAmount, callbackData);

        assertGt(expectedRefund, 0);
        assertEq(borrowToken.balanceOf(LIQUIDATOR), stableBefore + expectedRefund);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
    }
}
