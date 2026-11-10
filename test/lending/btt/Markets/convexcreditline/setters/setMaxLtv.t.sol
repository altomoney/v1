// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

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
}
