// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IAltoCreditMarketErrors, IAltoCreditMarketEvents} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";
import {CreditLineCallForwarderMock} from "../mocks/CreditLineCallForwarderMock.sol";

contract AltoConvexCreditLineMarketSetCreditLimitTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setCreditLimit(1);
    }

    function test_RevertZeroBeforeAccrual() external {
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setCreditLimit(0);
        assertEq(market.creditLimit(), CREDIT_LIMIT);
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
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
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

        assertEq(market.creditLimit(), 500 ether);
    }

    function test_FrozenStillAccruesAndAcceptsDebtBoundary() external {
        _openPosition(1_000 ether, 500 ether);
        _pause(FROZEN_TYPE);
        _mockAccrual(10 ether, 123);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(123, 10 ether, 510 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoCreditMarketEvents.SetCreditLimit(CREDIT_LIMIT, 510 ether);
        vm.prank(OWNER);
        market.setCreditLimit(510 ether);

        assertEq(market.creditLimit(), 510 ether);
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 510 ether);
        assertEq(market.claimableFeesAssets(), 10 ether);
    }

    function test_ValidIncreaseDecreaseMaximumAndUnchangedValue() external {
        vm.startPrank(OWNER);
        market.setCreditLimit(CREDIT_LIMIT + 1);
        market.setCreditLimit(CREDIT_LIMIT - 1);
        market.setCreditLimit(type(uint128).max);
        vm.expectEmit(address(market));
        emit IAltoCreditMarketEvents.SetCreditLimit(type(uint128).max, type(uint128).max);
        market.setCreditLimit(type(uint128).max);
        vm.stopPrank();

        assertEq(market.creditLimit(), type(uint128).max);
        (, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyShares, 0);
        (, uint128 borrowShares) = market.totalBorrowed();
        assertEq(borrowShares, 0);
        assertEq(rewardPool.withdrawCalls(), 0);
        assertEq(booster.depositCalls(), 0);
    }

    function test_RejectsIrmReentrancyAndRollsBack() external {
        CreditLineCallForwarderMock callback = new CreditLineCallForwarderMock(address(market), CREDIT_ACCOUNT);
        vm.mockFunction(address(irm), address(callback), abi.encodeWithSelector(IIrm.updateInterestRate.selector));
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.setCreditLimit(CREDIT_LIMIT + 1);

        _assertUnchanged(beforeState);
    }
}
