// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {IAltoConvexCreditLineEvents} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";
import {CreditLineMarketCollateralTokenMock} from "./mocks/CreditLineMarketCollateralTokenMock.sol";

contract AltoConvexCreditLineMarketAddRewardTokenTest is ConvexCreditLineCommon {
    uint256 private constant MAX_REWARD_TOKENS = 16;

    function test_RevertWhenCallerIsNotOwner() external {
        CreditLineMarketCollateralTokenMock token = new CreditLineMarketCollateralTokenMock("R", "R");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.addRewardToken(address(token));
    }

    function test_RevertForZeroNoCodeAndReservedTokens() external {
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.addRewardToken(address(0));
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(USER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(collateralToken));
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(borrowToken));
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(depositToken));
        vm.stopPrank();
        assertEq(market.rewardTokenCount(), 2);
    }

    function test_RevertForDuplicateWithoutChangingList() external {
        address[] memory beforeList = _configuredRewards();
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(primaryRewardToken));
        _assertRewardList(beforeList);
    }

    function test_EnforcesMaximumRewardTokenCount() external {
        vm.startPrank(OWNER);
        for (uint256 i = market.rewardTokenCount(); i < MAX_REWARD_TOKENS; ++i) {
            market.addRewardToken(address(new CreditLineMarketCollateralTokenMock("R", "R")));
        }
        CreditLineMarketCollateralTokenMock overflowToken = new CreditLineMarketCollateralTokenMock("Overflow", "OVER");
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(overflowToken));
        vm.stopPrank();
        assertEq(market.rewardTokenCount(), MAX_REWARD_TOKENS);
    }

    function test_AppendsContractWithoutCallingItsErc20Methods() external {
        address token = address(oracle);
        AccountingState memory beforeState = _state();
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineEvents.RewardTokenAdded(token);
        vm.prank(OWNER);
        market.addRewardToken(token);

        assertEq(market.rewardTokenCount(), 3);
        assertEq(market.rewardToken(2), token);
        assertTrue(market.isRewardToken(token));
        _assertUnchanged(beforeState);
    }

    function test_RemovedTokenCanBeAddedAgainAtEnd() external {
        vm.prank(OWNER);
        market.removeRewardToken(address(extraRewardToken));
        vm.prank(OWNER);
        market.addRewardToken(address(extraRewardToken));
        assertEq(market.rewardToken(market.rewardTokenCount() - 1), address(extraRewardToken));
    }

    function test_RemainsCallableWhilePausedFrozenOrInactive() external {
        CreditLineMarketCollateralTokenMock first = new CreditLineMarketCollateralTokenMock("First", "ONE");
        CreditLineMarketCollateralTokenMock second = new CreditLineMarketCollateralTokenMock("Second", "TWO");
        CreditLineMarketCollateralTokenMock third = new CreditLineMarketCollateralTokenMock("Third", "THREE");

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.addRewardToken(address(first));
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.addRewardToken(address(second));
        _unpause(FROZEN_TYPE);
        _exitConvex();
        vm.prank(OWNER);
        market.addRewardToken(address(third));

        assertTrue(market.isRewardToken(address(first)));
        assertTrue(market.isRewardToken(address(second)));
        assertTrue(market.isRewardToken(address(third)));
    }
}
