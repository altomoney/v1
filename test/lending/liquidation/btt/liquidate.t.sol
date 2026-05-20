// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {ILiquidationPeripheryErrors} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_Liquidate_Test is LiquidationPeripheryCommon {
    struct LiquidatorBalances {
        uint256 borrow;
        uint256 collateral;
        uint256 underlying;
    }

    function _liquidatorBalances() internal view returns (LiquidatorBalances memory balances) {
        balances.borrow = borrowToken.balanceOf(LIQUIDATOR);
        balances.collateral = collateralToken.balanceOf(LIQUIDATOR);
        balances.underlying = underlyingToken.balanceOf(LIQUIDATOR);
    }

    function _liquidateViaPeriphery(IMarket target, address borrower, bool repayViaUsm)
        internal
        returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee)
    {
        vm.prank(LIQUIDATOR);
        return periphery.liquidate(address(target), borrower, repayViaUsm, "");
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
        (uint256 assetSpent,,,) = usm.getAssetAmountForSellAsset(repaidBorrow);

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
        periphery.liquidate(unregistered, BORROWER, false, "");
    }

    function test_WhenBorrowMarket_ReturnsLiquidationAmountsFromMarket() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(borrowMarket, true, borrower);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(borrowMarket, borrower, false);

        _assertDirectRepayOutcome(borrowMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsFalse_LiquidatesWithBorrowToken() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(borrowMarket, true, borrower);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(borrowMarket, borrower, false);

        _assertDirectRepayOutcome(borrowMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsTrue_AndStableBoughtEqualsBorrowAmount() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(borrowMarket, true, borrower);
        _configureUsmOneToOne();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(borrowMarket, borrower, true);

        _assertUsmEqualRepayOutcome(borrowMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenBorrowMarket_AndRepayViaUsmIsTrue_AndStableBoughtExceedsBorrowAmount_RefundsLiquidator() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(borrowMarket, true, borrower);
        _configureUsmExcessSell();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(borrowMarket, borrower, true);

        _assertUsmExcessRepayOutcome(
            borrowMarket, before, seized, repaid, protocolFee, _expectedStableRefund(repaid)
        );
    }

    function test_WhenMintMarket_ReturnsLiquidationAmountsFromMarket() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(mintMarket, false, borrower);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(mintMarket, borrower, false);

        _assertDirectRepayOutcome(mintMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsFalse_LiquidatesWithBorrowToken() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(mintMarket, false, borrower);
        _fundLiquidatorForDirectRepay();
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(mintMarket, borrower, false);

        _assertDirectRepayOutcome(mintMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsTrue_AndStableBoughtEqualsBorrowAmount() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(mintMarket, false, borrower);
        _configureUsmOneToOne();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(mintMarket, borrower, true);

        _assertUsmEqualRepayOutcome(mintMarket, before, seized, repaid, protocolFee);
    }

    function test_WhenMintMarket_AndRepayViaUsmIsTrue_AndStableBoughtExceedsBorrowAmount_RefundsLiquidator() public {
        address borrower = _nextBorrower();
        _createInsolventPosition(mintMarket, false, borrower);
        _configureUsmExcessSell();
        _fundLiquidatorForUsmRepay(100 ether);
        LiquidatorBalances memory before = _liquidatorBalances();

        (uint256 seized, uint256 repaid, uint256 protocolFee) = _liquidateViaPeriphery(mintMarket, borrower, true);

        _assertUsmExcessRepayOutcome(
            mintMarket, before, seized, repaid, protocolFee, _expectedStableRefund(repaid)
        );
    }
}
