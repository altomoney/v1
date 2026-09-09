// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoCreditMarketErrors, IAltoCreditMarketEvents} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetBorrowOpeningFeeTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setBorrowOpeningFee(1);
    }

    function test_RevertAboveMaximumWithoutChangingState() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setBorrowOpeningFee(MATH_PRECISION + 1);
        assertEq(market.borrowOpeningFee(), 0);
    }

    function test_SetsInclusiveBoundsAndEmitsEvenWhenUnchanged() external {
        _mockIrmUpdateRevert();
        vm.expectEmit(address(market));
        emit IAltoCreditMarketEvents.SetBorrowOpeningFee(0, MATH_PRECISION);
        vm.prank(OWNER);
        market.setBorrowOpeningFee(MATH_PRECISION);
        assertEq(market.borrowOpeningFee(), MATH_PRECISION);

        vm.expectEmit(address(market));
        emit IAltoCreditMarketEvents.SetBorrowOpeningFee(MATH_PRECISION, MATH_PRECISION);
        vm.prank(OWNER);
        market.setBorrowOpeningFee(MATH_PRECISION);

        vm.prank(OWNER);
        market.setBorrowOpeningFee(0);
        assertEq(market.borrowOpeningFee(), 0);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_NewFeeAffectsOnlyLaterBorrowsAndWorksWhilePausedOrFrozen() external {
        _openPosition(1_000 ether, 100 ether);
        (, uint128 sharesBefore,) = market.position(CREDIT_ACCOUNT);

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setBorrowOpeningFee(0.1 ether);
        assertEq(market.borrowOpeningFee(), 0.1 ether);
        (, uint128 sharesAfter,) = market.position(CREDIT_ACCOUNT);
        assertEq(sharesAfter, sharesBefore);

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setBorrowOpeningFee(0.2 ether);
        assertEq(market.borrowOpeningFee(), 0.2 ether);

        _unpause(FROZEN_TYPE);
        vm.prank(CREDIT_ACCOUNT);
        (,, uint256 openingFee) = market.borrow(10 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");
        assertEq(openingFee, 2 ether);
    }
}
