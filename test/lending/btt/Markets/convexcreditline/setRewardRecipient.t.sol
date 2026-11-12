// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetRewardRecipientTest is ConvexCreditLineCommon {
    function test_OnlyExactCreditAccountCanSetRecipient() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(USER);
        vm.prank(DELEGATE);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(USER);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(USER);
    }

    function test_CreditAccountCannotSetZeroRecipient() external {
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.setRewardRecipient(address(0));
    }

    function test_UpdatesAndEmitsIncludingUnchangedValue() external {
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetRewardRecipient(REWARD_RECIPIENT, USER);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        assertEq(market.rewardRecipient(), USER);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetRewardRecipient(USER, USER);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        assertEq(market.rewardRecipient(), USER);
    }

    function test_SubsequentClaimsUseNewRecipient() external {
        deal(address(primaryRewardToken), address(market), 3 ether);
        deal(address(extraRewardToken), address(market), 5 ether);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        market.claimRewards();
        assertEq(primaryRewardToken.balanceOf(USER), 3 ether);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(extraRewardToken.balanceOf(USER), 5 ether);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(primaryRewardToken.balanceOf(address(market)), 0);
        assertEq(extraRewardToken.balanceOf(address(market)), 0);
    }

    function test_RemainsCallableWhilePausedFrozenOrInactive() external {
        _pause(PAUSE_TYPE);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);
        assertEq(market.rewardRecipient(), USER);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(RECEIVER);
        assertEq(market.rewardRecipient(), RECEIVER);
        _unpause(FROZEN_TYPE);
        _exitConvex();
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(REWARD_RECIPIENT);
        assertEq(market.rewardRecipient(), REWARD_RECIPIENT);
    }

    function test_RedirectsTreasuryShareOfOutstandingFeesToNewRecipient() external {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(USER);

        vm.prank(REWARD_RECIPIENT);
        uint256 claimed = market.claimInterest(0);

        assertEq(claimed, 10 ether);
        assertEq(borrowToken.balanceOf(USER), 3 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(market.claimableFeesAssets(), 0);
    }
}
