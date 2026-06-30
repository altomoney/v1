// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./btt/LiquidationPeriphery/LiquidationPeripheryCommon.t.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev End-to-end liquidation through `LiquidationPeriphery` on a real borrow market.
/// @dev Borrow token (DUSD) is 18 decimals; USM underlying (USDC) is 6 decimals.
contract LiquidationPeripheryTest is LiquidationPeripheryCommon {
    uint256 internal constant PERIPHERY_SELL_FEE_BPS = 100;

    struct Balances {
        uint256 borrow;
        uint256 collateral;
        uint256 underlying;
    }

    function _balances(address account) internal view returns (Balances memory b) {
        b.borrow = borrowToken.balanceOf(account);
        b.collateral = collateralToken.balanceOf(account);
        b.underlying = underlyingToken.balanceOf(account);
    }

    function _liquidate(bytes memory liquidationPeripheryCallbackData)
        internal
        returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee)
    {
        vm.prank(LIQUIDATOR);
        return simpleLiquidator.liquidateMarket(
            address(borrowMarket), BORROWER, address(usm), "", liquidationPeripheryCallbackData
        );
    }

    function _configurePeripherySellFee(uint256 feeBps) internal {
        AdvancedPermissionsFeeStrategy feeStrategy = AdvancedPermissionsFeeStrategy(usm.getFeeStrategy());
        vm.startPrank(OWNER);
        feeStrategy.setSellFeeByRoleHash(
            SELL_SWAPPER_ROLE,
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: uint16(feeBps)})
        );
        feeStrategy.setUserSellFeeRole(address(periphery), SELL_SWAPPER_ROLE);
        vm.stopPrank();
    }

    function _assertLiquidationSucceeded(uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee)
        internal
        pure
    {
        assertGt(seizedCollateral, 0);
        assertGt(repaidBorrow, 0);
        assertGt(protocolFee, 0);
        assertGt(seizedCollateral, protocolFee);
    }

    function _assertPeripheryClean() internal view {
        assertEq(borrowToken.balanceOf(address(periphery)), 0);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
        assertEq(borrowToken.allowance(address(periphery), address(borrowMarket)), 0);
        _assertUnderlyingApprovalResetToUsm();
    }

    function _assertZeroApprovalToPeriphery(address owner, address token) internal view {
        assertEq(IERC20(token).allowance(owner, address(periphery)), 0);
    }

    function _nominalUsdcForRepay(uint256 repaidBorrow) internal pure returns (uint256) {
        return repaidBorrow / 1e12;
    }

    function _fundSimpleLiquidatorForEmptyCallback(uint256 repayAmountBound) internal {
        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(repayAmountBound, address(periphery));
        _transferUnderlyingFromSwapperToSimpleLiquidator(assetAmount);
        vm.prank(address(simpleLiquidator));
        underlyingToken.approve(address(periphery), type(uint256).max);
    }

    /// @dev Liquidates with sell fee enabled for periphery and above one to one price.
    function test_Liquidate_PeripherySellFeeAndAboveOneToOnePrice() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmExcessSell();
        _configurePeripherySellFee(PERIPHERY_SELL_FEE_BPS);
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        Balances memory before = _balances(address(simpleLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidate("");

        (uint256 quotedUnderlying, uint256 stableBought,, uint256 sellFee) =
            usm.getAssetAmountForSellAsset(repaid, address(periphery));
        uint256 expectedStableRefund = _expectedStableRefund(repaid);

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertGt(expectedStableRefund, 0, "excess stable from above-1:1 USM price");
        assertGt(stableBought, repaid, "USM pays more stable than 1:1 for the quoted sell");
        assertGt(sellFee, 0, "periphery sell fee is charged");
        assertEq(
            AdvancedPermissionsFeeStrategy(usm.getFeeStrategy()).getSellFeeForUser(address(periphery)),
            PERIPHERY_SELL_FEE_BPS
        );
        assertEq(collateralToken.balanceOf(address(simpleLiquidator)) - before.collateral, seized - protocolFee);
        assertEq(before.underlying - underlyingToken.balanceOf(address(simpleLiquidator)), quotedUnderlying);
        assertEq(borrowToken.balanceOf(address(simpleLiquidator)) - before.borrow, expectedStableRefund);
        _assertPeripheryClean();
    }

    /// @dev Fuzzes USM buy/sell fees and prior swap activity, then asserts periphery `onLiquidateCallback` leaves no underlying asset on periphery.
    function testFuzz_OnLiquidateCallback_NoUnderlyingDustOnPeriphery(
        uint256 buyFeeBps,
        uint256 sellFeeBps,
        uint256 priceRatio,
        uint256 preSellUnderlying,
        uint256 preBuyMinUnderlying,
        uint256 preSellUnderlying2,
        uint256 repayAmount
    ) public {
        buyFeeBps = bound(buyFeeBps, 0, MAX_USM_FEE_BPS);
        sellFeeBps = bound(sellFeeBps, 0, MAX_USM_FEE_BPS);
        priceRatio = bound(priceRatio, 50e16, 105e18);
        preSellUnderlying = bound(preSellUnderlying, 1e6, 10_000e6);
        preBuyMinUnderlying = bound(preBuyMinUnderlying, 0, preSellUnderlying);
        preSellUnderlying2 = bound(preSellUnderlying2, 0, 10_000e6);
        repayAmount = bound(repayAmount, 1, 10000 ether);

        _configureUsmFees(buyFeeBps, sellFeeBps);
        _configureUsmPriceRatio(priceRatio);
        _warmupUsmSwaps(preSellUnderlying, preBuyMinUnderlying, preSellUnderlying2);

        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));

        bytes memory peripheryCallbackData = _liquidationCallbackData(address(borrowMarket));
        uint256 collateralAmount = 1 ether;
        _simulateMarketCollateralTransferToLiquidator(address(simpleLiquidator), collateralAmount);

        _invokeOnLiquidateCallback(
            address(borrowMarket),
            repayAmount,
            collateralAmount,
            _callbackData(address(simpleLiquidator), address(borrowMarket), address(usm), peripheryCallbackData)
        );

        assertEq(simpleLiquidator.callbackCallCount(), 1);
        assertEq(simpleLiquidator.lastAssetsToRepay(), quotedUnderlying);
        assertEq(simpleLiquidator.lastCollateralReceived(), collateralAmount);
        assertEq(simpleLiquidator.lastCallbackData(), peripheryCallbackData);
        assertEq(collateralToken.balanceOf(address(simpleLiquidator)), 0);
        assertEq(underlyingToken.balanceOf(address(simpleLiquidator)), 0);
        assertLt(
            borrowToken.balanceOf(address(simpleLiquidator)),
            1e15,
            "simpleLiquidator should have less than 1e15 borrow tokens refunded"
        );
        _assertZeroApprovalToPeriphery(address(simpleLiquidator), address(underlyingToken));
        assertEq(
            underlyingToken.balanceOf(address(periphery)), 0, "there should be no underlying asset dust on periphery"
        );
        _assertUnderlyingApprovalResetToUsm();
    }

    /// @dev Quote via `getAssetAmountForSellAsset`, sell quoted underlying on USM, assert stable out is within 1e15 of `repayAmount`.
    function testFuzz_GetAssetAmountForSellAsset_MatchesSellAsset(
        uint256 sellFeeBps,
        uint256 priceRatio,
        uint256 repayAmount
    ) public {
        sellFeeBps = bound(sellFeeBps, 0, MAX_USM_FEE_BPS);
        priceRatio = bound(priceRatio, 95e16, 105e18);
        repayAmount = bound(repayAmount, 1, 1000_000 ether);

        _configureUsmFees(0, sellFeeBps);
        _configureUsmPriceRatio(priceRatio);

        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));
        vm.assume(quotedUnderlying > 0);
        vm.assume(quotedUnderlying <= usm.getAvailableUnderlyingExposure());

        vm.prank(OWNER);
        underlyingToken.mint(address(periphery), quotedUnderlying);
        vm.prank(address(periphery));
        underlyingToken.approve(address(usm), quotedUnderlying);

        vm.prank(address(periphery));
        (, uint256 stableBought) = usm.sellAsset(quotedUnderlying, address(periphery));

        uint256 diff = stableBought - repayAmount;
        assertLe(diff, 1e15, "stable bought deviates from repay amount");
    }
}
