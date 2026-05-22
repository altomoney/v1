// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_Liquidate_Test is LiquidationPeripheryCommon {
    struct LiquidatorBalances {
        uint256 borrow;
        uint256 collateral;
        uint256 underlying;
    }

    function _liquidatorBalances(address liquidator) internal view returns (LiquidatorBalances memory balances) {
        balances.borrow = borrowToken.balanceOf(liquidator);
        balances.collateral = collateralToken.balanceOf(liquidator);
        balances.underlying = underlyingToken.balanceOf(liquidator);
    }

    function _liquidateViaSimpleLiquidator(
        IMarket target,
        address borrower,
        address targetUsm,
        bytes memory liquidationPeripheryCallbackData
    ) internal returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee) {
        _expectLiquidationEvent(target, address(simpleLiquidator), borrower);

        vm.prank(LIQUIDATOR);
        return simpleLiquidator.liquidateMarket(
            address(target), borrower, targetUsm, "", liquidationPeripheryCallbackData
        );
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

    function _assertCollateralTransferredTo(address liquidator, uint256 collateralBefore, uint256 netCollateral)
        internal
        view
    {
        assertEq(collateralToken.balanceOf(liquidator) - collateralBefore, netCollateral);
    }

    function _assertPeripheryClean() internal view {
        assertEq(borrowToken.balanceOf(address(periphery)), 0);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
        _assertUnderlyingApprovalResetToUsm();
    }

    function _assertBorrowApprovalResetToMarket(IMarket target) internal view {
        assertEq(borrowToken.allowance(address(periphery), address(target)), 0);
    }

    function _assertZeroApprovalToPeriphery(address tokenOwner, address token) internal view {
        assertEq(IERC20(token).allowance(tokenOwner, address(periphery)), 0);
    }

    function _expectLiquidationEvent(IMarket target, address liquidator, address borrower) internal {
        vm.expectEmit(true, true, true, false);
        emit ILiquidationPeripheryEvents.Liquidation(address(target), liquidator, borrower, 0, 0, 0);
    }

    function _assertUsmLiquidationOutcome(
        IMarket target,
        LiquidatorBalances memory before,
        uint256 seizedCollateral,
        uint256 repaidBorrow,
        uint256 protocolFee,
        uint256 expectedStableRefund
    ) internal {
        address liquidator = address(simpleLiquidator);
        (uint256 assetSpent,,,) = usm.getAssetAmountForSellAsset(repaidBorrow, address(periphery));

        _assertCollateralTransferredTo(liquidator, before.collateral, seizedCollateral - protocolFee);
        assertEq(before.underlying - underlyingToken.balanceOf(liquidator), assetSpent);

        if (expectedStableRefund > 0) {
            assertEq(borrowToken.balanceOf(liquidator) - before.borrow, expectedStableRefund);
        } else {
            assertEq(borrowToken.balanceOf(liquidator), before.borrow);
        }

        _assertBorrowApprovalResetToMarket(target);
        _assertPeripheryClean();
    }

    function _assertUsmLiquidationOutcomeAfterSwapCallback(
        IMarket target,
        LiquidatorBalances memory before,
        uint256 repaidBorrow,
        uint256 expectedStableRefund
    ) internal {
        address liquidator = address(simpleLiquidator);

        assertEq(collateralToken.balanceOf(liquidator), 0);
        assertEq(underlyingToken.balanceOf(liquidator), 0);

        if (expectedStableRefund > 0) {
            assertEq(borrowToken.balanceOf(liquidator) - before.borrow, expectedStableRefund);
        } else {
            assertEq(borrowToken.balanceOf(liquidator), before.borrow);
        }

        _assertBorrowApprovalResetToMarket(target);
        _assertPeripheryClean();
    }

    function _setupBorrowMarketLiquidation() internal {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmOneToOne();
    }

    function _setupMintMarketLiquidation() internal {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _configureUsmOneToOne();
    }

    function _fundSimpleLiquidatorForEmptyCallback(uint256 repayAmountBound) internal {
        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(repayAmountBound, address(periphery));
        _transferUnderlyingFromSwapperToSimpleLiquidator(assetAmount);
        vm.prank(address(simpleLiquidator));
        underlyingToken.approve(address(periphery), type(uint256).max);
    }

    function test_RevertWhen_MarketIsNotSupported() public {
        address unsupported = makeAddr("UnsupportedMarket");

        vm.prank(LIQUIDATOR);
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        simpleLiquidator.liquidateMarket(unsupported, BORROWER, address(usm), "", "");
    }

    function test_GivenLiquidationPeripheryCallbackDataIsEmpty_WhenBorrowMarket() public {
        _setupBorrowMarketLiquidation();
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(borrowMarket, BORROWER, address(usm), "");

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(simpleLiquidator.callbackCallCount(), 0);
        _assertUsmLiquidationOutcome(borrowMarket, before, seized, repaid, protocolFee, 0);
    }

    function test_GivenLiquidationPeripheryCallbackDataIsNotEmpty_WhenBorrowMarket() public {
        _setupBorrowMarketLiquidation();
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        bytes memory callbackData = _liquidationCallbackData(address(borrowMarket));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(borrowMarket, BORROWER, address(usm), callbackData);

        (uint256 expectedUnderlying,,,) = usm.getAssetAmountForSellAsset(repaid, address(periphery));

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(simpleLiquidator.callbackCallCount(), 1);
        assertEq(simpleLiquidator.lastAssetsToRepay(), expectedUnderlying);
        assertEq(simpleLiquidator.lastCollateralReceived(), seized - protocolFee);
        assertEq(simpleLiquidator.lastUnderlyingAsset(), address(underlyingToken));
        assertEq(simpleLiquidator.lastUnderlyingAmount(), expectedUnderlying);
        assertEq(simpleLiquidator.lastCallbackData(), callbackData);
        _assertZeroApprovalToPeriphery(address(simpleLiquidator), address(underlyingToken));
        _assertUsmLiquidationOutcomeAfterSwapCallback(borrowMarket, before, repaid, 0);
    }

    function test_WhenStableTokenBoughtEqualsBorrowAmount_WhenBorrowMarket() public {
        _setupBorrowMarketLiquidation();
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        (, uint256 stableBought,,) = usm.getAssetAmountForSellAsset(100 ether, address(periphery));
        assertEq(stableBought, 100 ether);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(borrowMarket, BORROWER, address(usm), "");

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        _assertUsmLiquidationOutcome(borrowMarket, before, seized, repaid, protocolFee, 0);
    }

    function test_WhenStableTokenBoughtExceedsBorrowAmount_WhenBorrowMarket() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmExcessSell();
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(borrowMarket, BORROWER, address(usm), "");

        uint256 expectedRefund = _expectedStableRefund(repaid);
        assertGt(expectedRefund, 0);

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        _assertUsmLiquidationOutcome(borrowMarket, before, seized, repaid, protocolFee, expectedRefund);
    }

    function test_GivenLiquidationPeripheryCallbackDataIsEmpty_WhenMintMarket() public {
        _setupMintMarketLiquidation();
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(mintMarket, BORROWER, address(usm), "");

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(simpleLiquidator.callbackCallCount(), 0);
        _assertUsmLiquidationOutcome(mintMarket, before, seized, repaid, protocolFee, 0);
    }

    function test_GivenLiquidationPeripheryCallbackDataIsNotEmpty_WhenMintMarket() public {
        _setupMintMarketLiquidation();
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        bytes memory callbackData = _liquidationCallbackData(address(mintMarket));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(mintMarket, BORROWER, address(usm), callbackData);

        (uint256 expectedUnderlying,,,) = usm.getAssetAmountForSellAsset(repaid, address(periphery));

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        assertEq(simpleLiquidator.callbackCallCount(), 1);
        assertEq(simpleLiquidator.lastAssetsToRepay(), expectedUnderlying);
        assertEq(simpleLiquidator.lastCollateralReceived(), seized - protocolFee);
        assertEq(simpleLiquidator.lastUnderlyingAsset(), address(underlyingToken));
        assertEq(simpleLiquidator.lastUnderlyingAmount(), expectedUnderlying);
        assertEq(simpleLiquidator.lastCallbackData(), callbackData);
        _assertZeroApprovalToPeriphery(address(simpleLiquidator), address(underlyingToken));
        _assertUsmLiquidationOutcomeAfterSwapCallback(mintMarket, before, repaid, 0);
    }

    function test_WhenStableTokenBoughtEqualsBorrowAmount_WhenMintMarket() public {
        _setupMintMarketLiquidation();
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(mintMarket, BORROWER, address(usm), "");

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        _assertUsmLiquidationOutcome(mintMarket, before, seized, repaid, protocolFee, 0);
    }

    function test_WhenStableTokenBoughtExceedsBorrowAmount_WhenMintMarket() public {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _configureUsmExcessSell();
        _fundSimpleLiquidatorForEmptyCallback(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(address(simpleLiquidator));

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaSimpleLiquidator(mintMarket, BORROWER, address(usm), "");

        uint256 expectedRefund = _expectedStableRefund(repaid);
        assertGt(expectedRefund, 0);

        _assertLiquidationSucceeded(seized, repaid, protocolFee);
        _assertUsmLiquidationOutcome(mintMarket, before, seized, repaid, protocolFee, expectedRefund);
    }
}
