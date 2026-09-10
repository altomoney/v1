// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetForeclosureLtvTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setForeclosureLtv(0.95 ether);
    }

    function test_RevertAtOrBelowMaxLtvAndAboveMaximum() external {
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setForeclosureLtv(MAX_LTV - 1);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setForeclosureLtv(MAX_LTV);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setForeclosureLtv(MATH_PRECISION + 1);
        vm.stopPrank();
    }

    function test_SetsValidLtvAndEmitsEvenWhenUnchanged() external {
        uint256 newLtv = 0.95 ether;
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetForeclosureLtv(FORECLOSURE_LTV, newLtv);
        vm.prank(OWNER);
        market.setForeclosureLtv(newLtv);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetForeclosureLtv(newLtv, newLtv);
        vm.prank(OWNER);
        market.setForeclosureLtv(newLtv);
        assertEq(market.foreclosureLtv(), newLtv);
    }
}
