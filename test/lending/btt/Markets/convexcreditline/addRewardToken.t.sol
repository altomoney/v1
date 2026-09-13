// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vm} from "forge-std/Vm.sol";

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
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
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(0));
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(collateralToken));
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(borrowToken));
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(depositToken));
        vm.stopPrank();
        _assertRewardTokenCount(2);
    }

    function test_RevertForDuplicateWithoutChangingList() external {
        address[] memory beforeList = _configuredRewards(2);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(primaryRewardToken));
        _assertRewardList(beforeList);
    }

    function test_EnforcesMaximumRewardTokenCount() external {
        vm.startPrank(OWNER);
        for (uint256 i = 2; i < MAX_REWARD_TOKENS; ++i) {
            market.addRewardToken(address(new CreditLineMarketCollateralTokenMock("R", "R")));
        }
        CreditLineMarketCollateralTokenMock overflowToken = new CreditLineMarketCollateralTokenMock("Overflow", "OVER");
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addRewardToken(address(overflowToken));
        vm.stopPrank();
        _assertRewardTokenCount(MAX_REWARD_TOKENS);
    }

    function test_AppendsContractWithoutCallingItsErc20Methods() external {
        address token = address(oracle);
        AccountingState memory beforeState = _state();
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.RewardTokenAdded(token);
        vm.recordLogs();
        vm.prank(OWNER);
        market.addRewardToken(token);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(market));
        assertEq(logs[0].topics[0], IAltoConvexCreditLineMarketEvents.RewardTokenAdded.selector);

        _assertRewardTokenCount(3);
        assertEq(market.rewardToken(2), token);
        assertTrue(market.isRewardToken(token));
        _assertUnchanged(beforeState);
    }

    function test_RemovedTokenCanBeAddedAgainAtEnd() external {
        vm.prank(OWNER);
        market.removeRewardToken(address(extraRewardToken));
        vm.prank(OWNER);
        market.addRewardToken(address(extraRewardToken));
        assertEq(market.rewardToken(1), address(extraRewardToken));
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
