// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
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
        _mockIrmUpdateRevert();
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

    function test_CanLowerThresholdAcrossExistingDebtAndWorksInAllPauseStates() external {
        _openPosition(1_000 ether, 740 ether);
        _mockAccrual(30 ether, 1);
        market.accrueInterest();
        _mockAccrual(0, 1);
        AccountingState memory beforeState = _state();

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setForeclosureLtv(0.8 ether);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setForeclosureLtv(0.76 ether);

        AccountingState memory afterState = _state();
        assertEq(afterState.totalBorrowed.assets, beforeState.totalBorrowed.assets);
        assertEq(afterState.creditPosition.collateralAssets, beforeState.creditPosition.collateralAssets);
        assertEq(market.foreclosureLtv(), 0.76 ether);

        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
    }
}
