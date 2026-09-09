// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {IAltoConvexCreditLineEvents} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";
import {CreditLineMarketCollateralTokenMock} from "./mocks/CreditLineMarketCollateralTokenMock.sol";

contract AltoConvexCreditLineMarketRemoveRewardTokenTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwnerBeforeExternalChecks() external {
        vm.mockCallRevert(address(rewardPool), abi.encodeCall(IConvexRewardPool.rewardToken, ()), "MUST_NOT_CALL");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.removeRewardToken(address(extraRewardToken));
        vm.clearMockedCalls();
    }

    function test_RevertForUnconfiguredBeforeExternalChecks() external {
        vm.mockCallRevert(address(rewardPool), abi.encodeCall(IConvexRewardPool.rewardToken, ()), "MUST_NOT_CALL");
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.removeRewardToken(USER);
        vm.clearMockedCalls();
    }

    function test_RevertForCurrentPrimaryWithoutQueryingBalance() external {
        vm.mockCallRevert(
            address(primaryRewardToken),
            abi.encodeCall(primaryRewardToken.balanceOf, (address(market))),
            "MUST_NOT_CALL"
        );
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.removeRewardToken(address(primaryRewardToken));
        vm.clearMockedCalls();
    }

    function test_RevertForAnyNonzeroMarketTokenBalance() external {
        deal(address(extraRewardToken), address(market), 1);
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.removeRewardToken(address(extraRewardToken));
        assertTrue(market.isRewardToken(address(extraRewardToken)));

        deal(address(extraRewardToken), address(market), 1 ether);
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.removeRewardToken(address(extraRewardToken));
    }

    function test_ExternalQueryFailuresPreserveList() external {
        address[] memory beforeList = _configuredRewards();
        vm.mockCallRevert(address(rewardPool), abi.encodeCall(IConvexRewardPool.rewardToken, ()), "REWARD_REVERTED");
        vm.prank(OWNER);
        vm.expectRevert(bytes("REWARD_REVERTED"));
        market.removeRewardToken(address(extraRewardToken));
        vm.clearMockedCalls();
        _assertRewardList(beforeList);

        vm.mockCall(address(rewardPool), abi.encodeCall(IConvexRewardPool.rewardToken, ()), hex"01");
        vm.prank(OWNER);
        vm.expectRevert();
        market.removeRewardToken(address(extraRewardToken));
        vm.clearMockedCalls();
        _assertRewardList(beforeList);

        vm.mockCall(address(extraRewardToken), abi.encodeCall(extraRewardToken.balanceOf, (address(market))), hex"01");
        vm.prank(OWNER);
        vm.expectRevert();
        market.removeRewardToken(address(extraRewardToken));
        vm.clearMockedCalls();
        _assertRewardList(beforeList);
    }

    function test_RemovingLastPopsAndRemovingMiddleUsesSwapAndPop() external {
        CreditLineMarketCollateralTokenMock third = new CreditLineMarketCollateralTokenMock("Third", "THIRD");
        vm.prank(OWNER);
        market.addRewardToken(address(third));

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineEvents.RewardTokenRemoved(address(third));
        vm.prank(OWNER);
        market.removeRewardToken(address(third));
        assertEq(market.rewardTokenCount(), 2);
        assertEq(market.rewardToken(1), address(extraRewardToken));

        vm.prank(OWNER);
        market.addRewardToken(address(third));
        vm.prank(OWNER);
        market.removeRewardToken(address(extraRewardToken));
        assertEq(market.rewardTokenCount(), 2);
        assertEq(market.rewardToken(0), address(primaryRewardToken));
        assertEq(market.rewardToken(1), address(third));
        assertFalse(market.isRewardToken(address(extraRewardToken)));
        assertTrue(market.isRewardToken(address(third)));
    }

    function test_RemovedTokenCanBeReaddedAndIsExcludedFromClaims() external {
        vm.prank(OWNER);
        market.removeRewardToken(address(extraRewardToken));
        deal(address(extraRewardToken), address(market), 5 ether);
        market.claimRewards();
        assertEq(extraRewardToken.balanceOf(address(market)), 5 ether);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 0);

        vm.prank(OWNER);
        market.addRewardToken(address(extraRewardToken));
        assertEq(market.rewardToken(market.rewardTokenCount() - 1), address(extraRewardToken));
    }

    function test_DynamicPrimaryTokenControlsWhichTokenIsProtected() external {
        rewardPool.setPoolMetadata(POOL_ID, address(booster), address(depositToken), address(extraRewardToken));
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.removeRewardToken(address(extraRewardToken));

        vm.prank(OWNER);
        market.removeRewardToken(address(primaryRewardToken));
        assertFalse(market.isRewardToken(address(primaryRewardToken)));
    }

    function test_RemainsCallableInAllPauseAndStrategyStates() external {
        CreditLineMarketCollateralTokenMock one = new CreditLineMarketCollateralTokenMock("One", "ONE");
        CreditLineMarketCollateralTokenMock two = new CreditLineMarketCollateralTokenMock("Two", "TWO");
        CreditLineMarketCollateralTokenMock three = new CreditLineMarketCollateralTokenMock("Three", "THREE");
        vm.startPrank(OWNER);
        market.addRewardToken(address(one));
        market.addRewardToken(address(two));
        market.addRewardToken(address(three));
        vm.stopPrank();

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.removeRewardToken(address(one));
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.removeRewardToken(address(two));
        _unpause(FROZEN_TYPE);
        _exitConvex();
        vm.prank(OWNER);
        market.removeRewardToken(address(three));
    }
}
