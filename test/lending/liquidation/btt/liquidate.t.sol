// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {
    SimpleLiquidationPeripheryCallback
} from "@alto-test/lending/liquidation/helpers/SimpleLiquidationPeripheryCallback.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidationPeripheryErrors} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_Liquidate_Test is LiquidationPeripheryCommon {
    bytes internal constant NON_EMPTY_CALLBACK_DATA = hex"01";

    SimpleLiquidationPeripheryCallback internal callbackLiquidator;

    struct LiquidatorBalances {
        uint256 borrow;
        uint256 collateral;
        uint256 underlying;
    }

    function setUp() public virtual override {
        super.setUp();
        callbackLiquidator = new SimpleLiquidationPeripheryCallback(address(periphery));
    }

    function _liquidatorBalances(address liquidator) internal view returns (LiquidatorBalances memory balances) {
        balances.borrow = borrowToken.balanceOf(liquidator);
        balances.collateral = collateralToken.balanceOf(liquidator);
        balances.underlying = underlyingToken.balanceOf(liquidator);
    }

    function _liquidateViaPeriphery(
        IMarket target,
        address borrower,
        bool repayViaUsm,
        address liquidator,
        bytes memory liquidationPeripheryCallbackData
    ) internal returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee) {
        vm.prank(liquidator);
        return periphery.liquidate(address(target), borrower, repayViaUsm, "", liquidationPeripheryCallbackData);
    }

    function _assertZeroApprovalToPeriphery(address tokenOwner, address token) internal view {
        assertEq(IERC20(token).allowance(tokenOwner, address(periphery)), 0);
    }

    function _assertDirectRepayOutcome(
        IMarket target,
        LiquidatorBalances memory before,
        uint256 seizedCollateral,
        uint256 repaidBorrow,
        uint256 protocolFee
    ) internal {
        assertEq(collateralToken.balanceOf(LIQUIDATOR) - before.collateral, seizedCollateral - protocolFee);
        assertEq(before.borrow - borrowToken.balanceOf(LIQUIDATOR), repaidBorrow);
        assertEq(borrowToken.allowance(address(periphery), address(target)), 0);
    }

    function _assertUsmEqualRepayOutcome(
        IMarket target,
        LiquidatorBalances memory before,
        uint256 seizedCollateral,
        uint256 repaidBorrow,
        uint256 protocolFee
    ) internal {
        (uint256 assetSpent,,,) = usm.getAssetAmountForSellAsset(repaidBorrow, address(periphery));

        assertEq(collateralToken.balanceOf(LIQUIDATOR) - before.collateral, seizedCollateral - protocolFee);
        assertEq(before.underlying - underlyingToken.balanceOf(LIQUIDATOR), assetSpent);
        assertEq(borrowToken.balanceOf(LIQUIDATOR), before.borrow);
        assertEq(borrowToken.allowance(address(periphery), address(target)), 0);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function _assertUsmExcessRepayOutcome(
        IMarket target,
        LiquidatorBalances memory before,
        uint256 seizedCollateral,
        uint256 repaidBorrow,
        uint256 protocolFee,
        uint256 expectedStableRefund
    ) internal {
        assertEq(collateralToken.balanceOf(LIQUIDATOR) - before.collateral, seizedCollateral - protocolFee);
        assertEq(borrowToken.balanceOf(LIQUIDATOR) - before.borrow, expectedStableRefund);
        assertEq(borrowToken.allowance(address(periphery), address(target)), 0);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function test_RevertWhen_MarketIsNotRegistered() public {
        address unregistered = makeAddr("UnregisteredMarket");

        vm.prank(LIQUIDATOR);
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.liquidate(unregistered, BORROWER, false, "", "");
    }

    function test_WhenBorrowMarket_ReturnsLiquidationAmountsFromMarket() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, false, LIQUIDATOR, "");

        _assertDirectRepayOutcome(borrowMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsFalse_LiquidatesWithBorrowToken() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, false, LIQUIDATOR, "");

        _assertDirectRepayOutcome(borrowMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsTrue_AndStableBoughtEqualsBorrowAmount() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmOneToOne();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, true, LIQUIDATOR, "");

        _assertUsmEqualRepayOutcome(borrowMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsTrue_AndStableBoughtExceedsBorrowAmount_RefundsLiquidator() public {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmExcessSell();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, true, LIQUIDATOR, "");

        _assertUsmExcessRepayOutcome(borrowMarket, before, seized, repaid, protocolFee, _expectedStableRefund(repaid));
    }

    function test_WhenMintMarket_ReturnsLiquidationAmountsFromMarket() public {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, false, LIQUIDATOR, "");

        _assertDirectRepayOutcome(mintMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsFalse_LiquidatesWithBorrowToken() public {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, false, LIQUIDATOR, "");

        _assertDirectRepayOutcome(mintMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsTrue_AndStableBoughtEqualsBorrowAmount() public {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _configureUsmOneToOne();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, true, LIQUIDATOR, "");

        _assertUsmEqualRepayOutcome(mintMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsTrue_AndStableBoughtExceedsBorrowAmount_RefundsLiquidator() public {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _configureUsmExcessSell();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances(LIQUIDATOR);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, true, LIQUIDATOR, "");

        _assertUsmExcessRepayOutcome(mintMarket, before, seized, repaid, protocolFee, _expectedStableRefund(repaid));
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsFalse_AndLiquidationPeripheryCallbackDataIsEmpty_DoesNotCallCallback()
        public
    {
        _createInsolventPosition(borrowMarket, true, BORROWER);

        _mintBorrowToken(address(callbackLiquidator), 100 ether);
        vm.prank(address(callbackLiquidator));
        borrowToken.approve(address(periphery), type(uint256).max);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, false, address(callbackLiquidator), "");

        assertEq(callbackLiquidator.callbackCallCount(), 0);
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsFalse_AndLiquidationPeripheryCallbackDataIsNotEmpty_CallsCallbackAndClearsApproval()
        public
    {
        _createInsolventPosition(borrowMarket, true, BORROWER);

        _mintBorrowToken(address(callbackLiquidator), 100 ether);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, false, address(callbackLiquidator), NON_EMPTY_CALLBACK_DATA);

        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastAssetToSend(), address(borrowToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), repaid);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(borrowToken));
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsTrue_AndLiquidationPeripheryCallbackDataIsEmpty_DoesNotCallCallback()
        public
    {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmOneToOne();

        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(100 ether, address(periphery));
        underlyingToken.mint(address(callbackLiquidator), assetAmount * 2);
        vm.prank(address(callbackLiquidator));
        underlyingToken.approve(address(periphery), type(uint256).max);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, true, address(callbackLiquidator), "");

        assertEq(callbackLiquidator.callbackCallCount(), 0);
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsTrue_AndLiquidationPeripheryCallbackDataIsNotEmpty_CallsCallbackAndClearsApproval()
        public
    {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _configureUsmOneToOne();

        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(100 ether, address(periphery));
        underlyingToken.mint(address(callbackLiquidator), assetAmount * 2);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(borrowMarket, BORROWER, true, address(callbackLiquidator), NON_EMPTY_CALLBACK_DATA);
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repaid, address(periphery));

        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastAssetToSend(), address(underlyingToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), quotedUnderlying);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(underlyingToken));
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsFalse_AndLiquidationPeripheryCallbackDataIsEmpty_DoesNotCallCallback()
        public
    {
        _createInsolventPosition(mintMarket, false, BORROWER);

        _mintBorrowToken(address(callbackLiquidator), 100 ether);
        vm.prank(address(callbackLiquidator));
        borrowToken.approve(address(periphery), type(uint256).max);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, false, address(callbackLiquidator), "");

        assertEq(callbackLiquidator.callbackCallCount(), 0);
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsFalse_AndLiquidationPeripheryCallbackDataIsNotEmpty_CallsCallbackAndClearsApproval()
        public
    {
        _createInsolventPosition(mintMarket, false, BORROWER);

        _mintBorrowToken(address(callbackLiquidator), 100 ether);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, false, address(callbackLiquidator), NON_EMPTY_CALLBACK_DATA);

        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastAssetToSend(), address(borrowToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), repaid);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(borrowToken));
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsTrue_AndLiquidationPeripheryCallbackDataIsEmpty_DoesNotCallCallback()
        public
    {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _configureUsmOneToOne();

        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(100 ether, address(periphery));
        underlyingToken.mint(address(callbackLiquidator), assetAmount * 2);
        vm.prank(address(callbackLiquidator));
        underlyingToken.approve(address(periphery), type(uint256).max);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, true, address(callbackLiquidator), "");

        assertEq(callbackLiquidator.callbackCallCount(), 0);
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsTrue_AndLiquidationPeripheryCallbackDataIsNotEmpty_CallsCallbackAndClearsApproval()
        public
    {
        _createInsolventPosition(mintMarket, false, BORROWER);
        _configureUsmOneToOne();

        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(100 ether, address(periphery));
        underlyingToken.mint(address(callbackLiquidator), assetAmount * 2);

        (uint256 seized, uint256 repaid, uint256 protocolFee) =
            _liquidateViaPeriphery(mintMarket, BORROWER, true, address(callbackLiquidator), NON_EMPTY_CALLBACK_DATA);
        (uint256 quotedUnderlying,,,) = usm.getAssetAmountForSellAsset(repaid, address(periphery));

        assertEq(callbackLiquidator.callbackCallCount(), 1);
        assertEq(callbackLiquidator.lastAssetToSend(), address(underlyingToken));
        assertEq(callbackLiquidator.lastAssetAmountToSend(), quotedUnderlying);
        _assertZeroApprovalToPeriphery(address(callbackLiquidator), address(underlyingToken));
        assertEq(collateralToken.balanceOf(address(callbackLiquidator)), seized - protocolFee);
        assertEq(underlyingToken.balanceOf(address(periphery)), 0);
    }
}
