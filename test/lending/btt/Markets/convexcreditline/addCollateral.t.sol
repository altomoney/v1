// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(0, USER);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(1, USER);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(1, address(0));

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addCollateral(0, CREDIT_ACCOUNT);
    }

    function test_RevertWhenCallerIsUnrelated() external {
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(1, CREDIT_ACCOUNT);
    }

    function test_RevertWhenCallerIsAuthorizedDelegate() external {
        vm.prank(DELEGATE);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(1, CREDIT_ACCOUNT);
    }

    function test_RevertWhenInactiveWithoutTransferOrAccountingChange() external {
        _exitConvex();
        _unpause(PAUSE_TYPE);
        deal(address(collateralToken), CREDIT_ACCOUNT, 10 ether);
        vm.prank(CREDIT_ACCOUNT);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);

        _assertUnchanged(beforeState);
        assertEq(collateralToken.balanceOf(CREDIT_ACCOUNT), 10 ether);
    }

    function test_BoosterRevertAndFalseAreAtomic() external {
        deal(address(collateralToken), CREDIT_ACCOUNT, 20 ether);
        vm.prank(CREDIT_ACCOUNT);
        collateralToken.approve(address(market), type(uint256).max);
        AccountingState memory beforeState = _state();

        booster.setDepositBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("DEPOSIT_REVERTED"));
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);

        booster.setDepositBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.addCollateral(10 ether, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_ValidDepositsPreserveExistingIdleStakeAndUpdateOnlyCreditPosition() external {
        deal(address(collateralToken), address(market), 3 ether);
        deal(address(collateralToken), address(rewardPool), 5 ether);
        rewardPool.setStake(address(market), 5 ether);
        deal(address(collateralToken), CREDIT_ACCOUNT, 17 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        collateralToken.approve(address(market), type(uint256).max);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.CollateralStaked(CREDIT_ACCOUNT, 17 ether);
        vm.expectEmit(address(market));
        emit IMarketEvents.AddCollateral(CREDIT_ACCOUNT, CREDIT_ACCOUNT, 17 ether);
        uint256 returnedAssets = market.addCollateral(17 ether, CREDIT_ACCOUNT);
        vm.stopPrank();

        (,, uint128 collateralAssets) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralToken.balanceOf(CREDIT_ACCOUNT), 0);
        assertEq(collateralAssets, 17 ether);
        assertEq(collateralToken.balanceOf(address(market)), 3 ether);
        assertEq(rewardPool.balanceOf(address(market)), 22 ether);
        assertEq(booster.depositCalls(), 1);
        assertEq(booster.lastPid(), POOL_ID);
        assertEq(booster.lastAmount(), 17 ether);
        assertTrue(booster.lastStake());
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
        assertEq(returnedAssets, 17 ether);
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyAssets, CREDIT_LIMIT);
        assertEq(supplyShares, 0);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
    }
}
