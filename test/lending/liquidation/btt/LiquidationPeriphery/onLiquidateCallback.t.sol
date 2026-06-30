// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidationPeripheryErrors} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_OnLiquidateCallback_Test is LiquidationPeripheryCommon {
    function _assertCollateralUnchangedOnLiquidator(address liquidator, uint256 expectedBalance) internal view {
        assertEq(collateralToken.balanceOf(liquidator), expectedBalance);
        assertEq(collateralToken.balanceOf(address(periphery)), 0);
    }

    function _assertBorrowTokenApprovedToMarket(IMarket target, uint256 repayAmount) internal view {
        assertEq(borrowToken.allowance(address(periphery), address(target)), repayAmount);
        assertEq(borrowToken.balanceOf(address(periphery)), repayAmount);
    }

    function _assertZeroApprovalToPeriphery(address tokenOwner, address token) internal view {
        assertEq(IERC20(token).allowance(tokenOwner, address(periphery)), 0);
    }

    function _assertPeripheryHasNoUnderlyingDust() internal view {
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function test_RevertWhen_CallerIsNotASupportedMarket() public {
        bytes memory callbackData = _callbackData(address(simpleLiquidator), address(borrowMarket), address(usm), "");

        vm.prank(makeAddr("RandomCaller"));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_RevertWhen_MarketInCallbackDataDoesNotMatchCaller() public {
        bytes memory callbackData = _callbackData(address(simpleLiquidator), address(mintMarket), address(usm), "");

        vm.prank(address(borrowMarket));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_RevertWhen_UsmIsNotInRegistry() public {
        vm.startPrank(OWNER);
        DUSD otherStable = new DUSD(address(endpoints[1]), OWNER);
        DUSDAdvancedPermissionsUsm otherUsm =
            _deployUsm(address(otherStable), address(underlyingToken), ONE_TO_ONE_PRICE_RATIO);
        vm.stopPrank();

        bytes memory callbackData =
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(otherUsm), "");

        vm.prank(address(borrowMarket));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_RevertWhen_UsmStableTokenDoesNotMatchBorrowToken() public {
        vm.startPrank(OWNER);
        DUSD otherStable = new DUSD(address(endpoints[1]), OWNER);
        DUSDAdvancedPermissionsUsm otherUsm =
            _deployUsm(address(otherStable), address(underlyingToken), ONE_TO_ONE_PRICE_RATIO);
        vm.stopPrank();

        vm.prank(OWNER);
        usmRegistry.addUsm(address(otherUsm));

        bytes memory callbackData =
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(otherUsm), "");

        vm.prank(address(borrowMarket));
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.onLiquidateCallback(1 ether, 1 ether, callbackData);
    }

    function test_GivenLiquidationPeripheryCallbackDataIsEmpty() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));

        _simulateMarketCollateralTransferToLiquidator(address(simpleLiquidator), collateralAmount);
        _configureUsmOneToOne();
        _transferUnderlyingFromSwapperToSimpleLiquidator(quotedUnderlying);
        vm.prank(address(simpleLiquidator));
        underlyingToken.approve(address(periphery), quotedUnderlying);

        uint256 underlyingBefore = underlyingToken.balanceOf(address(simpleLiquidator));
        uint256 stableBefore = borrowToken.balanceOf(address(simpleLiquidator));

        _invokeOnLiquidateCallback(
            address(borrowMarket),
            repayAmount,
            collateralAmount,
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(usm), "")
        );

        _assertCollateralUnchangedOnLiquidator(address(simpleLiquidator), collateralAmount);
        assertEq(simpleLiquidator.callbackCallCount(), 0);
        assertEq(underlyingToken.balanceOf(address(simpleLiquidator)), underlyingBefore - quotedUnderlying);
        assertEq(borrowToken.balanceOf(address(simpleLiquidator)), stableBefore);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        _assertUnderlyingApprovalResetToUsm();
        _assertPeripheryHasNoUnderlyingDust();
    }

    function test_GivenLiquidationPeripheryCallbackDataIsNotEmpty() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));
        bytes memory peripheryCallbackData = _liquidationCallbackData(address(borrowMarket));

        _simulateMarketCollateralTransferToLiquidator(address(simpleLiquidator), collateralAmount);
        _configureUsmOneToOne();

        _invokeOnLiquidateCallback(
            address(borrowMarket),
            repayAmount,
            collateralAmount,
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(usm), peripheryCallbackData)
        );

        assertEq(collateralToken.balanceOf(address(simpleLiquidator)), 0);
        assertEq(simpleLiquidator.callbackCallCount(), 1);
        assertEq(simpleLiquidator.lastAssetsToRepay(), quotedUnderlying);
        assertEq(simpleLiquidator.lastCollateralReceived(), collateralAmount);
        assertEq(simpleLiquidator.lastUnderlyingAsset(), address(underlyingToken));
        assertEq(simpleLiquidator.lastUnderlyingAmount(), quotedUnderlying);
        assertEq(simpleLiquidator.lastCallbackData(), peripheryCallbackData);
        _assertZeroApprovalToPeriphery(address(simpleLiquidator), address(underlyingToken));
        assertEq(underlyingToken.balanceOf(address(simpleLiquidator)), 0);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        _assertUnderlyingApprovalResetToUsm();
        _assertPeripheryHasNoUnderlyingDust();
    }

    function test_WhenStableTokenBoughtEqualsBorrowAmount_DoesNotRefundStableToLiquidator() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        _simulateMarketCollateralTransferToLiquidator(address(simpleLiquidator), collateralAmount);

        _configureUsmOneToOne();
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));
        _transferUnderlyingFromSwapperToSimpleLiquidator(quotedUnderlying);
        vm.prank(address(simpleLiquidator));
        underlyingToken.approve(address(periphery), quotedUnderlying);

        (, uint256 stableBought,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));
        assertEq(stableBought, repayAmount);

        uint256 stableBefore = borrowToken.balanceOf(address(simpleLiquidator));

        _invokeOnLiquidateCallback(
            address(borrowMarket),
            repayAmount,
            collateralAmount,
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(usm), "")
        );

        _assertCollateralUnchangedOnLiquidator(address(simpleLiquidator), collateralAmount);
        assertEq(borrowToken.balanceOf(address(simpleLiquidator)), stableBefore);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        _assertUnderlyingApprovalResetToUsm();
        _assertPeripheryHasNoUnderlyingDust();
    }

    function test_WhenStableTokenBoughtExceedsBorrowAmount_RefundsExcessStableToLiquidator() public {
        uint256 repayAmount = 1 ether;
        uint256 collateralAmount = 1 ether;
        _simulateMarketCollateralTransferToLiquidator(address(simpleLiquidator), collateralAmount);

        _configureUsmExcessSell();
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));
        _transferUnderlyingFromSwapperToSimpleLiquidator(quotedUnderlying);
        vm.prank(address(simpleLiquidator));
        underlyingToken.approve(address(periphery), quotedUnderlying);

        uint256 expectedRefund = _expectedStableRefund(repayAmount);
        assertGt(expectedRefund, 0);

        uint256 stableBefore = borrowToken.balanceOf(address(simpleLiquidator));

        _invokeOnLiquidateCallback(
            address(borrowMarket),
            repayAmount,
            collateralAmount,
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(usm), "")
        );

        _assertCollateralUnchangedOnLiquidator(address(simpleLiquidator), collateralAmount);
        assertEq(borrowToken.balanceOf(address(simpleLiquidator)), stableBefore + expectedRefund);
        _assertBorrowTokenApprovedToMarket(borrowMarket, repayAmount);
        _assertUnderlyingApprovalResetToUsm();
        _assertPeripheryHasNoUnderlyingDust();
        assertEq(borrowToken.balanceOf(address(periphery)), repayAmount);
    }
}
