// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    IAltoConvexCreditLineErrors,
    IAltoConvexCreditLineEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";
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
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(0, USER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
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
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
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

    function test_CollateralBalanceQueryFailureRollsBackPosition() external {
        deal(address(collateralToken), USER, 10 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        bytes memory query = abi.encodeCall(collateralToken.balanceOf, (address(market)));

        vm.mockCallRevert(address(collateralToken), query, "BALANCE_REVERTED");
        vm.prank(USER);
        vm.expectRevert(bytes("BALANCE_REVERTED"));
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        vm.clearMockedCalls();
        (,, uint128 collateralAssets) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAssets, 0);

        vm.mockCall(address(collateralToken), query, hex"01");
        vm.prank(USER);
        vm.expectRevert();
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        vm.clearMockedCalls();
        (,, collateralAssets) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAssets, 0);
    }

    function test_RawLpDecreaseDuringReceivePanicsAndRollsBack() external {
        deal(address(collateralToken), address(market), 1 ether);
        deal(address(collateralToken), USER, 1 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        collateralToken.setTransferBehavior(false, false, 10_000, 2 ether);
        AccountingState memory beforeState = _state();

        vm.prank(USER);
        vm.expectRevert();
        market.addCollateral(1 ether, CREDIT_ACCOUNT);

        _assertUnchanged(beforeState);
    }

    function test_RevertForUnexpectedRawLpReceiveDelta() external {
        deal(address(collateralToken), USER, 20 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        collateralToken.setTransferBehavior(false, false, 9_000, 0);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        collateralToken.setTransferBehavior(false, false, 11_000, 0);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_BoosterRevertFalseAndBadIdleDeltaAreAtomic() external {
        deal(address(collateralToken), USER, 30 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        booster.setDepositBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(USER);
        vm.expectRevert(bytes("DEPOSIT_REVERTED"));
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        booster.setDepositBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        booster.setDepositBehavior(false, true, 9 ether, 10 ether);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_RevertForUnexpectedStakedDeltaAndMalformedStakeQuery() external {
        deal(address(collateralToken), USER, 30 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        booster.setDepositBehavior(false, true, 10 ether, 9 ether);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        vm.mockCall(address(rewardPool), abi.encodeCall(IConvexRewardPool.balanceOf, (address(market))), hex"01");
        vm.prank(USER);
        vm.expectRevert();
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        vm.clearMockedCalls();
        _assertUnchanged(beforeState);
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
        emit IAltoConvexCreditLineEvents.CollateralStaked(USER, 10 ether);
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
        assertEq(market.idleCollateralAssets(), 3 ether);
        assertEq(market.stakedCollateralAssets(), 22 ether);
        assertEq(booster.depositCalls(), 2);
        assertEq(booster.lastPid(), POOL_ID);
        assertEq(booster.lastAmount(), 7 ether);
        assertTrue(booster.lastStake());
        assertEq(returnedAssets, 7 ether);
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyAssets, CREDIT_LIMIT);
        assertEq(supplyShares, 0);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
    }
}
