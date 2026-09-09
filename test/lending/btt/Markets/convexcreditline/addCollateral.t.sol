// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketAddCollateralTest is ConvexCreditLineCommon {
    function test_RevertWhenPausedOrFrozen() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.addCollateral(1, CREDIT_ACCOUNT);

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        _assertPausedRevert(FROZEN_TYPE);
        market.addCollateral(1, CREDIT_ACCOUNT);
    }

    function test_CreditAccountCheckPrecedesBaseAmountValidation() external {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(0, USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(1, address(0));

        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addCollateral(0, CREDIT_ACCOUNT);
    }

    function test_RevertWhenInactiveWithoutTransferOrAccountingChange() external {
        _exitConvex();
        _unpause(PAUSE_TYPE);
        deal(address(collateralToken), USER, 10 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);

        _assertUnchanged(beforeState);
        assertEq(collateralToken.balanceOf(USER), 10 ether);
    }

    function test_TransferBalanceAndAllowanceFailuresAreAtomic() external {
        AccountingState memory beforeState = _state();
        vm.prank(USER);
        vm.expectRevert();
        market.addCollateral(1, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        deal(address(collateralToken), USER, 1);
        vm.prank(USER);
        vm.expectRevert();
        market.addCollateral(1, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_PositionUint128OverflowRevertsBeforeExternalCalls() external {
        bytes32 positionBase = keccak256(abi.encode(CREDIT_ACCOUNT, uint256(8)));
        vm.store(address(market), bytes32(uint256(positionBase) + 1), bytes32(uint256(type(uint128).max)));
        uint256 depositsBefore = booster.depositCalls();

        vm.expectRevert();
        market.addCollateral(1, CREDIT_ACCOUNT);

        (,, uint128 collateralAssets) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAssets, type(uint128).max);
        assertEq(booster.depositCalls(), depositsBefore);
    }

    function test_BoosterRevertAndFalseAreAtomic() external {
        deal(address(collateralToken), USER, 20 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        booster.setDepositBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(USER);
        vm.expectRevert(bytes("DEPOSIT_REVERTED"));
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);

        booster.setDepositBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_TemporaryBoosterApprovalFailuresAreAtomic() external {
        deal(address(collateralToken), USER, 10 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        collateralToken.setApproveFailure(true);
        vm.prank(USER);
        vm.expectRevert(bytes("APPROVE_REVERTED"));
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        collateralToken.setApproveFailure(false);
        _assertUnchanged(beforeState);
        assertEq(booster.depositCalls(), 0);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);

        booster.setCallback(address(collateralToken), abi.encodeCall(collateralToken.setApproveFailure, (true)));
        vm.prank(USER);
        vm.expectRevert(bytes("APPROVE_REVERTED"));
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
        assertEq(booster.depositCalls(), 0);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_TemporaryBoosterApprovalCapsEachDeposit() external {
        deal(address(collateralToken), address(market), 3 ether);
        deal(address(collateralToken), USER, 10 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        booster.setDepositBehavior(false, true, 11 ether, type(uint256).max);
        AccountingState memory beforeState = _state();

        vm.prank(USER);
        vm.expectRevert();
        market.addCollateral(10 ether, CREDIT_ACCOUNT);

        _assertUnchanged(beforeState);
        assertEq(collateralToken.balanceOf(USER), 10 ether);
        assertEq(booster.depositCalls(), 0);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_RejectsBoosterReentrancyAtomically() external {
        deal(address(collateralToken), USER, 20 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        booster.setCallback(address(market), abi.encodeCall(market.addCollateral, (1, CREDIT_ACCOUNT)));
        AccountingState memory beforeState = _state();

        vm.prank(USER);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);

        _assertUnchanged(beforeState);
    }

    function test_ValidDepositsPreserveExistingIdleStakeAndUpdateOnlyCreditPosition() external {
        deal(address(collateralToken), address(market), 3 ether);
        deal(address(collateralToken), address(rewardPool), 5 ether);
        rewardPool.setStake(address(market), 5 ether);
        deal(address(collateralToken), USER, 10 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.CollateralStaked(USER, 10 ether);
        vm.expectEmit(address(market));
        emit IMarketEvents.AddCollateral(USER, CREDIT_ACCOUNT, 10 ether);
        vm.prank(USER);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        uint256 returnedAssets;
        deal(address(collateralToken), CREDIT_ACCOUNT, 7 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        collateralToken.approve(address(market), type(uint256).max);
        returnedAssets = market.addCollateral(7 ether, CREDIT_ACCOUNT);
        vm.stopPrank();

        (,, uint128 collateralAssets) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAssets, 17 ether);
        assertEq(collateralToken.balanceOf(address(market)), 3 ether);
        assertEq(market.stakedCollateralAssets(), 22 ether);
        assertEq(rewardPool.balanceOf(address(market)), 22 ether);
        assertEq(booster.depositCalls(), 2);
        assertEq(booster.lastPid(), POOL_ID);
        assertEq(booster.lastAmount(), 7 ether);
        assertTrue(booster.lastStake());
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
        assertEq(returnedAssets, 7 ether);
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyAssets, CREDIT_LIMIT);
        assertEq(supplyShares, 0);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
    }
}
