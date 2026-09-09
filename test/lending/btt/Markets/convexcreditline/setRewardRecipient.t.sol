// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {IAltoConvexCreditLineEvents} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetRewardRecipientTest is ConvexCreditLineCommon {
    function test_OnlyExactCreditAccountCanSetRecipient() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(USER);
        vm.prank(DELEGATE);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(USER);
        vm.prank(USER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(USER);
    }

    function test_CreditAccountCannotSetZeroRecipient() external {
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.setRewardRecipient(address(0));
    }

    function test_UpdatesAndEmitsIncludingUnchangedValue() external {
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineEvents.SetRewardRecipient(REWARD_RECIPIENT, USER);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        assertEq(market.rewardRecipient(), USER);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineEvents.SetRewardRecipient(USER, USER);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
    }

    function test_SubsequentClaimsUseNewRecipient() external {
        deal(address(primaryRewardToken), address(market), 3 ether);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        market.claimRewards();
        assertEq(primaryRewardToken.balanceOf(USER), 3 ether);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);
    }

    function test_RemainsCallableWhilePausedFrozenOrInactive() external {
        _pause(PAUSE_TYPE);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(RECEIVER);
        _unpause(FROZEN_TYPE);
        _exitConvex();
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(REWARD_RECIPIENT);
        assertEq(market.rewardRecipient(), REWARD_RECIPIENT);
    }
}
