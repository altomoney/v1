// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetMaxLtvTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setMaxLtv(1);
    }

    function test_RevertAtOrAboveForeclosureLtv() external {
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setMaxLtv(FORECLOSURE_LTV);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setMaxLtv(FORECLOSURE_LTV + 1);
        vm.stopPrank();
        assertEq(market.maxLtv(), MAX_LTV);
    }

    function test_SetsAnyValueBelowForeclosureAndEmitsEvenWhenUnchanged() external {
        _mockIrmUpdateRevert();
        vm.expectEmit(address(market));
        emit IMarketEvents.SetMaxLtv(MAX_LTV, 0);
        vm.prank(OWNER);
        market.setMaxLtv(0);
        assertEq(market.maxLtv(), 0);

        vm.expectEmit(address(market));
        emit IMarketEvents.SetMaxLtv(0, 0);
        vm.prank(OWNER);
        market.setMaxLtv(0);
    }

    function test_CanMakeExistingPositionInsolventAndWorksWhilePausedOrFrozen() external {
        _openPosition(1_000 ether, 500 ether);
        AccountingState memory beforeState = _state();

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setMaxLtv(0.4 ether);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setMaxLtv(0.3 ether);

        assertEq(market.maxLtv(), 0.3 ether);
        AccountingState memory afterState = _state();
        assertEq(afterState.totalBorrowed.assets, beforeState.totalBorrowed.assets);
        assertEq(afterState.creditPosition.borrowShares, beforeState.creditPosition.borrowShares);
        assertEq(rewardPool.withdrawCalls(), 0);
    }
}
