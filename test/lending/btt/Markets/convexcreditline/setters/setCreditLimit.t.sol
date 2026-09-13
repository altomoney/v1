// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAltoConvexCreditLineMarketEvents} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetCreditLimitTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setCreditLimit(1);
    }

    function test_AllowsZeroWhenNoDebtExistsAndAccruesFirst() external {
        _mockAccrual(0, 123);
        AccountingState memory expectedState = _state();
        expectedState.totalSupply.assets = 0;

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 0)));
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(123, 0, 0, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetCreditLimit(CREDIT_LIMIT, 0);
        vm.prank(OWNER);
        market.setCreditLimit(0);

        _assertStateEq(_state(), expectedState);
    }

    function test_AllowsZeroWhenPausedAndDebtFreeWithoutAccruing() external {
        _pause(PAUSE_TYPE);
        _mockIrmUpdateRevert();
        AccountingState memory expectedState = _state();
        expectedState.totalSupply.assets = 0;

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetCreditLimit(CREDIT_LIMIT, 0);
        vm.prank(OWNER);
        market.setCreditLimit(0);

        _assertStateEq(_state(), expectedState);
    }

    function test_RevertZeroWhenActiveDebtExists() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(10 ether, 123);
        AccountingState memory beforeState = _state();

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 100 ether)));
        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.setCreditLimit(0);

        _assertUnchanged(beforeState);
    }

    function test_RevertZeroWhenOnlyBadDebtRemains() external {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        _pause(PAUSE_TYPE);
        _mockIrmUpdateRevert();
        AccountingState memory beforeState = _state();
        assertEq(beforeState.totalBorrowed.assets, 0);
        assertEq(beforeState.badDebt, 100 ether);

        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.setCreditLimit(0);

        _assertUnchanged(beforeState);
    }

    function test_RevertOversizedLimitAtCheckedConversionAfterAccrual() external {
        AccountingState memory beforeState = _state();

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 0)));
        vm.prank(OWNER);
        vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
        market.setCreditLimit(uint256(type(uint128).max) + 1);

        _assertUnchanged(beforeState);
    }

    function test_AccruesBeforeDebtCheckAndRollsBackWhenNewLimitIsTooLow() external {
        _openPosition(1_000 ether, 500 ether);
        _mockAccrual(10 ether, 123);
        AccountingState memory beforeState = _state();

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 500 ether)));
        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.setCreditLimit(505 ether);

        _assertUnchanged(beforeState);
    }

    function test_RevertAtomicallyWhenIrmFails() external {
        _mockIrmUpdateRevert();
        AccountingState memory beforeState = _state();
        vm.prank(OWNER);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.setCreditLimit(CREDIT_LIMIT + 1);
        _assertUnchanged(beforeState);
    }

    function test_PausedSkipsAccrualAndComparesRecordedDebt() external {
        _openPosition(1_000 ether, 500 ether);
        _pause(PAUSE_TYPE);
        _mockAccrual(100 ether, 123);

        vm.prank(OWNER);
        market.setCreditLimit(500 ether);

        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(creditCapacity, 500 ether);
    }

    function test_PausedLimitBoundaryIncludesRecordedBadDebtWithoutAccruing() external {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(50 ether);
        _pause(PAUSE_TYPE);
        _mockIrmUpdateRevert();

        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.setCreditLimit(150 ether - 1);

        vm.prank(OWNER);
        market.setCreditLimit(150 ether);
        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(creditCapacity, 150 ether);
        assertEq(market.badDebtAssets(), 100 ether);
    }

    function test_UsesActiveDebtAndBadDebtForLimitBoundary() external {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 100 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(50 ether);

        AccountingState memory beforeState = _state();
        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.setCreditLimit(150 ether - 1);
        _assertUnchanged(beforeState);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(0, 0, 50 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetCreditLimit(CREDIT_LIMIT, 150 ether);
        vm.prank(OWNER);
        market.setCreditLimit(150 ether);

        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(creditCapacity, 150 ether);
        assertEq(market.badDebtAssets(), 100 ether);
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 50 ether);
    }

    function test_IncreasingLimitAfterForeclosureRestoresOnlyCapacityAboveBadDebt() external {
        vm.prank(OWNER);
        market.setCreditLimit(100 ether);
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        vm.prank(OWNER);
        market.setCreditLimit(150 ether);
        _mockAccrual(0, 0);
        _borrow(50 ether);

        (uint128 activeDebt,) = market.totalBorrowed();
        assertEq(activeDebt, 50 ether);
        assertEq(market.badDebtAssets(), 100 ether);
        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(uint256(activeDebt) + market.badDebtAssets(), creditCapacity);
    }

    function test_ValidIncreaseDecreaseMaximumAndUnchangedValue() external {
        vm.startPrank(OWNER);
        market.setCreditLimit(CREDIT_LIMIT + 1);
        market.setCreditLimit(CREDIT_LIMIT - 1);
        market.setCreditLimit(type(uint128).max);
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetCreditLimit(type(uint128).max, type(uint128).max);
        market.setCreditLimit(type(uint128).max);
        vm.stopPrank();

        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(creditCapacity, type(uint128).max);
        (, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyShares, 0);
        (, uint128 borrowShares) = market.totalBorrowed();
        assertEq(borrowShares, 0);
    }
}
