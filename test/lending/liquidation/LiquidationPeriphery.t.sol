// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./btt/LiquidationPeripheryCommon.t.sol";
import {
    SimpleLiquidationPeripheryCallback
} from "@alto-test/lending/liquidation/helpers/SimpleLiquidationPeripheryCallback.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Borrow token (DUSD) is 18 decimals; USM underlying (USDC) is 6 decimals.
contract LiquidationPeripheryTest is LiquidationPeripheryCommon {
    bytes internal constant NON_EMPTY_CALLBACK_DATA = hex"01";
    uint256 internal constant PERIPHERY_SELL_FEE_BPS = 100;

    SimpleLiquidationPeripheryCallback internal callbackLiquidator;

    struct Balances {
        uint256 borrow;
        uint256 collateral;
        uint256 underlying;
    }

    function setUp() public virtual override {
        super.setUp();
        callbackLiquidator = new SimpleLiquidationPeripheryCallback(address(periphery));
    }

    function _balances(address account) internal view returns (Balances memory b) {
        b.borrow = borrowToken.balanceOf(account);
        b.collateral = collateralToken.balanceOf(account);
        b.underlying = underlyingToken.balanceOf(account);
    }

    function _liquidate(address liquidator, bool repayViaUsm, bytes memory liquidationPeripheryCallbackData)
        internal
        returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee)
    {
        vm.prank(liquidator);
        return periphery.liquidate(address(borrowMarket), BORROWER, repayViaUsm, "", liquidationPeripheryCallbackData);
    }

    function _configurePeripherySellFee(uint256 feeBps) internal {
        AdvancedPermissionsFeeStrategy feeStrategy = AdvancedPermissionsFeeStrategy(usm.getFeeStrategy());
        vm.startPrank(OWNER);
        feeStrategy.setSellFeeByRoleHash(
            SELL_SWAPPER_ROLE, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: feeBps})
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
    }

    function _assertZeroApprovalToPeriphery(address owner, address token) internal view {
        assertEq(IERC20(token).allowance(owner, address(periphery)), 0);
    }

    function _nominalUsdcForRepay(uint256 repaidBorrow) internal pure returns (uint256) {
        return repaidBorrow / 1e12;
    }

    function test_Liquidate_RepayViaUsmFalse_EmptyCallbackData() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _fundLiquidatorForDirectRepay();
        Balances memory before = _balances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidate(LIQUIDATOR, false, "");

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(callbackLiquidator.callbackCallCount(), 0);
        assertEq(collateralToken.balanceOf(LIQUIDATOR) - before.collateral, seized - protocolFee);
        assertEq(before.borrow - borrowToken.balanceOf(LIQUIDATOR), repaid);
        _assertPeripheryClean();
    }

    function test_Liquidate_RepayViaUsmFalse_NonEmptyCallbackData() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _mintBorrowToken(address(callbackLiquidator), 100 ether);
        Balances memory before = _balances(address(callbackLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidate(address(callbackLiquidator), false, NON_EMPTY_CALLBACK_DATA);

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastAssetToSend(), address(borrowToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), repaid);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(borrowToken));
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)) - before.collateral, seized - protocolFee);
        assertEq(before.borrow - borrowToken.balanceOf(address(callbackLiquidator)), repaid);
        _assertPeripheryClean();
    }

    function test_Liquidate_RepayViaUsmTrue_EmptyCallbackData() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmOneToOne();
        _fundLiquidatorForUsmRepay(100 ether);
        Balances memory before = _balances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidate(LIQUIDATOR, true, "");

        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repaid, address(periphery));

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(callbackLiquidator.callbackCallCount(), 0);
        assertEq(collateralToken.balanceOf(LIQUIDATOR) - before.collateral, seized - protocolFee);
        assertEq(before.underlying - underlyingToken.balanceOf(LIQUIDATOR), quotedUnderlying);
        assertEq(borrowToken.balanceOf(LIQUIDATOR), before.borrow);
        assertGe(quotedUnderlying, _nominalUsdcForRepay(repaid));
        _assertPeripheryClean();
    }

    function test_Liquidate_RepayViaUsmTrue_NonEmptyCallbackData() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmOneToOne();
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(100 ether, address(periphery));
        underlyingToken.mint(address(callbackLiquidator), quotedUnderlying * 2);
        Balances memory before = _balances(address(callbackLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidate(address(callbackLiquidator), true, NON_EMPTY_CALLBACK_DATA);

        (uint256 expectedUnderlying,,,) = usm.getAssetAmountForSellAsset(repaid, address(periphery));

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastAssetToSend(), address(underlyingToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), expectedUnderlying);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(underlyingToken));
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)) - before.collateral, seized - protocolFee);
        assertEq(before.underlying - underlyingToken.balanceOf(address(callbackLiquidator)), expectedUnderlying);
        assertGe(expectedUnderlying, _nominalUsdcForRepay(repaid));
        assertEq(borrowToken.balanceOf(address(callbackLiquidator)), before.borrow);
        _assertPeripheryClean();
    }

    function test_Liquidate_RepayViaUsmTrue_WithPeripherySellFeeAndAboveOneToOnePrice() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmExcessSell();
        _configurePeripherySellFee(PERIPHERY_SELL_FEE_BPS);
        _fundLiquidatorForUsmRepay(100 ether);
        Balances memory before = _balances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidate(LIQUIDATOR, true, "");

        (uint256 quotedUnderlying, uint256 stableBought,, uint256 sellFee) =
            usm.getAssetAmountForSellAsset(repaid, address(periphery));
        uint256 expectedStableRefund = stableBought - repaid;

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertGt(expectedStableRefund, 0, "excess stable from above-1:1 USM price");
        assertGt(stableBought, repaid, "USM pays more stable than 1:1 for the quoted sell");
        assertGt(sellFee, 0, "periphery sell fee is charged");
        assertEq(
            AdvancedPermissionsFeeStrategy(usm.getFeeStrategy()).getSellFeeForUser(address(periphery)),
            PERIPHERY_SELL_FEE_BPS
        );
        assertEq(collateralToken.balanceOf(LIQUIDATOR) - before.collateral, seized - protocolFee);
        assertEq(before.underlying - underlyingToken.balanceOf(LIQUIDATOR), quotedUnderlying);
        assertEq(borrowToken.balanceOf(LIQUIDATOR) - before.borrow, expectedStableRefund);
        _assertPeripheryClean();
    }
}
