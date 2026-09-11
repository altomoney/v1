// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";
import {CreditLineMarketCollateralTokenMock} from "./mocks/CreditLineMarketCollateralTokenMock.sol";

contract AltoConvexCreditLineMarketClaimRewardsTest is ConvexCreditLineCommon {
    function test_PermissionlessAcrossPauseFreezeAndInactiveStates() external {
        vm.prank(USER);
        market.claimRewards();
        _pause(PAUSE_TYPE);
        vm.prank(USER);
        market.claimRewards();
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(USER);
        market.claimRewards();
        _unpause(FROZEN_TYPE);
        _exitConvex();
        vm.prank(USER);
        market.claimRewards();
        assertEq(rewardPool.getRewardCalls(), 4);
    }

    function test_CallsGetRewardWithMarketAndClaimExtrasTrue() external {
        market.claimRewards();
        assertEq(rewardPool.lastRewardAccount(), address(market));
        assertTrue(rewardPool.lastClaimExtras());
    }

    function test_GetRewardFailureDoesNotForwardExistingBalances() external {
        deal(address(primaryRewardToken), address(market), 3 ether);
        rewardPool.setRewardBehavior(true, true);
        vm.expectRevert(bytes("GET_REWARD_REVERTED"));
        market.claimRewards();
        assertEq(primaryRewardToken.balanceOf(address(market)), 3 ether);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);

        rewardPool.setRewardBehavior(false, false);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.claimRewards();
        assertEq(primaryRewardToken.balanceOf(address(market)), 3 ether);
    }

    function test_ZeroBalancesEmitAndReturnZeroForEveryConfiguredToken() external {
        vm.mockCallRevert(
            address(primaryRewardToken),
            abi.encodeCall(primaryRewardToken.transfer, (REWARD_RECIPIENT, 0)),
            bytes("ZERO_TRANSFER_MUST_NOT_BE_CALLED")
        );
        vm.mockCallRevert(
            address(extraRewardToken),
            abi.encodeCall(extraRewardToken.transfer, (REWARD_RECIPIENT, 0)),
            bytes("ZERO_TRANSFER_MUST_NOT_BE_CALLED")
        );

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.RewardsClaimed(
            address(this), REWARD_RECIPIENT, address(primaryRewardToken), 0
        );
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.RewardsClaimed(
            address(this), REWARD_RECIPIENT, address(extraRewardToken), 0
        );
        uint256[] memory amounts = market.claimRewards();
        assertEq(amounts.length, 2);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(primaryRewardToken.balanceOf(address(market)), 0);
        assertEq(extraRewardToken.balanceOf(address(market)), 0);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 0);
    }

    function test_ForwardsPreexistingAndNewRewardsInConfiguredOrder() external {
        deal(address(primaryRewardToken), address(market), 2 ether);
        address[] memory tokens = new address[](2);
        tokens[0] = address(primaryRewardToken);
        tokens[1] = address(extraRewardToken);
        uint256[] memory distributed = new uint256[](2);
        distributed[0] = 3 ether;
        distributed[1] = 7 ether;
        rewardPool.setRewards(tokens, distributed);

        uint256[] memory amounts = market.claimRewards();

        assertEq(amounts.length, 2);
        assertEq(amounts[0], 5 ether);
        assertEq(amounts[1], 7 ether);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 5 ether);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 7 ether);
        assertEq(primaryRewardToken.balanceOf(address(market)), 0);
        assertEq(extraRewardToken.balanceOf(address(market)), 0);
    }

    function test_ProcessesAllMaximumTokensOnceInOrder() external {
        CreditLineMarketCollateralTokenMock[] memory added = new CreditLineMarketCollateralTokenMock[](14);
        vm.startPrank(OWNER);
        for (uint256 i; i < added.length; ++i) {
            added[i] = new CreditLineMarketCollateralTokenMock("Reward", "R");
            market.addRewardToken(address(added[i]));
        }
        vm.stopPrank();
        for (uint256 i; i < added.length; ++i) {
            deal(address(added[i]), address(market), i + 1);
        }

        uint256[] memory amounts = market.claimRewards();
        assertEq(amounts.length, 16);
        for (uint256 i; i < added.length; ++i) {
            assertEq(market.rewardToken(i + 2), address(added[i]));
            assertEq(amounts[i + 2], i + 1);
            assertEq(added[i].balanceOf(REWARD_RECIPIENT), i + 1);
        }
    }

    function test_UnconfiguredAndRemovedRewardsRemainInMarket() external {
        CreditLineMarketCollateralTokenMock unconfigured =
            new CreditLineMarketCollateralTokenMock("Unconfigured", "NONE");
        deal(address(unconfigured), address(market), 5 ether);
        vm.prank(OWNER);
        market.removeRewardToken(address(extraRewardToken));
        deal(address(extraRewardToken), address(market), 7 ether);

        uint256[] memory amounts = market.claimRewards();

        assertEq(amounts.length, 1);
        assertEq(unconfigured.balanceOf(address(market)), 5 ether);
        assertEq(extraRewardToken.balanceOf(address(market)), 7 ether);
    }

    function test_SuccessDoesNotChangeAccountingConfigurationOrCustody() external {
        _addCollateral(10 ether);
        deal(address(primaryRewardToken), address(market), 3 ether);
        AccountingState memory beforeState = _state();
        address[] memory rewardsBefore = _configuredRewards(2);

        market.claimRewards();

        AccountingState memory afterState = _state();
        afterState.creditBalance = beforeState.creditBalance;
        _assertStateEq(afterState, beforeState);
        _assertRewardList(rewardsBefore);
        assertTrue(market.convexActive());
    }
}
