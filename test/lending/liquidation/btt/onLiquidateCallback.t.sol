// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {SimpleLiquidationPeripheryCallback} from "@alto-test/lending/liquidation/helpers/SimpleLiquidationPeripheryCallback.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidationPeripheryErrors} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_OnLiquidateCallback_Test is LiquidationPeripheryCommon {
    bytes internal constant NON_EMPTY_CALLBACK_DATA = hex"01";

    SimpleLiquidationPeripheryCallback internal callbackLiquidator;
    function setUp() public virtual override {
        super.setUp();
        callbackLiquidator = new SimpleLiquidationPeripheryCallback(address(periphery));
    }

    function _assertBorrowTokenApprovedToMarket(IMarket target, uint256 repayAmount) internal view {
        assertEq(borrowToken.allowance(address(periphery), address(target)), repayAmount);
        assertEq(borrowToken.balanceOf(address(periphery)), repayAmount);
    }

    function _assertZeroApprovalToPeriphery(address tokenOwner, address token) internal view {
        assertEq(IERC20(token).allowance(tokenOwner, address(periphery)), 0);
    }

    function test_RevertWhen_CallerIsNotRegisteredMarket() public {
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(borrowMarket), "");

        vm.prank(makeAddr("RandomCaller"));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_RevertWhen_MarketInCallbackDataDoesNotMatchCaller() public {
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(mintMarket), "");

        vm.prank(address(borrowMarket));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_TransfersCollateralToLiquidator() public {
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(borrowMarket), "");

        _fundLiquidatorForDirectRepay();

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(1 ether, collateralAmount, callbackData);

        assertEq(collateralToken.balanceOf(LIQUIDATOR), collateralAmount);
    }

    function test_WhenRepayViaUsmIsFalse_PullsBorrowTokenAndApprovesMarket() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);
        bytes memory callbackData = _callbackData(LIQUIDATOR, false, address(borrowMarket), "");

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

        bytes memory callbackData = _callbackData(LIQUIDATOR, true, address(borrowMarket), "");

        uint256 stableBefore = borrowToken.balanceOf(LIQUIDATOR);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(repayAmount, collateralAmount, callbackData);

        assertEq(borrowToken.balanceOf(LIQUIDATOR), stableBefore, "no stable refund when USM sells 1:1");
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
        assertEq(collateralToken.balanceOf(LIQUIDATOR), collateralAmount);
    }

    function test_WhenRepayViaUsmIsFalse_AndLiquidationPeripheryCallbackDataIsEmpty_DoesNotCallCallback() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);

        _mintBorrowToken(address(callbackLiquidator), 100 ether);
        vm.prank(address(callbackLiquidator));
        borrowToken.approve(address(periphery), repayAmount);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(
            repayAmount,
            collateralAmount,
            _callbackData(address(callbackLiquidator), false, address(borrowMarket), "")
        );

        assertEq(callbackLiquidator.callbackCallCount(), 0);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
    }

    function test_WhenRepayViaUsmIsFalse_AndLiquidationPeripheryCallbackDataIsNotEmpty_CallsCallbackAndClearsApproval()
        public
    {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        deal(address(collateralToken), address(periphery), collateralAmount);

        _mintBorrowToken(address(callbackLiquidator), repayAmount);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(
            repayAmount,
            collateralAmount,
            _callbackData(address(callbackLiquidator), false, address(borrowMarket), NON_EMPTY_CALLBACK_DATA)
        );

        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastCollateralReceived(), collateralAmount);
        assertEq(callbackLiquidator.lastAssetToSend(), address(borrowToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), repayAmount);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(borrowToken));
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), collateralAmount);
    }

    function test_WhenRepayViaUsmIsTrue_AndLiquidationPeripheryCallbackDataIsEmpty_DoesNotCallCallback() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));

        deal(address(collateralToken), address(periphery), collateralAmount);
        _configureUsmOneToOne();
        underlyingToken.mint(address(callbackLiquidator), quotedUnderlying);
        vm.prank(address(callbackLiquidator));
        underlyingToken.approve(address(periphery), quotedUnderlying);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(
            repayAmount,
            collateralAmount,
            _callbackData(address(callbackLiquidator), true, address(borrowMarket), "")
        );

        assertEq(callbackLiquidator.callbackCallCount(), 0);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function test_WhenRepayViaUsmIsTrue_AndLiquidationPeripheryCallbackDataIsNotEmpty_CallsCallbackAndClearsApproval()
        public
    {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));

        deal(address(collateralToken), address(periphery), collateralAmount);
        _configureUsmOneToOne();
        underlyingToken.mint(address(callbackLiquidator), quotedUnderlying);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(
            repayAmount,
            collateralAmount,
            _callbackData(address(callbackLiquidator), true, address(borrowMarket), NON_EMPTY_CALLBACK_DATA)
        );

        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastCollateralReceived(), collateralAmount);
        assertEq(callbackLiquidator.lastAssetToSend(), address(underlyingToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), quotedUnderlying);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(underlyingToken));
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), collateralAmount);
    }

    function test_WhenRepayViaUsmIsTrue_AndStableBoughtExceedsBorrowAmount_RefundsLiquidator() public {
        uint256 repayAmount = 1 ether;
        deal(address(collateralToken), address(periphery), repayAmount);

        _configureUsmExcessSell();
        _fundLiquidatorForUsmRepay(repayAmount);

        bytes memory callbackData = _callbackData(LIQUIDATOR, true, address(borrowMarket), "");

        uint256 stableBefore = borrowToken.balanceOf(LIQUIDATOR);
        uint256 expectedRefund = _expectedStableRefund(repayAmount);

        vm.prank(address(borrowMarket));
        periphery.onLiquidateCallback(repayAmount, repayAmount, callbackData);

        assertGt(expectedRefund, 0);
        assertEq(borrowToken.balanceOf(LIQUIDATOR), stableBefore + expectedRefund);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
    }
}
