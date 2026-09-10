// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetBorrowOpeningFeeTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setBorrowOpeningFee(1);
    }

    function test_RevertAboveMaximum() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setBorrowOpeningFee(MATH_PRECISION + 1);
    }

    function test_SetsAndEmitsEvenWhenUnchanged() external {
        uint256 newFee = 0.1 ether;
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetBorrowOpeningFee(0, newFee);
        vm.prank(OWNER);
        market.setBorrowOpeningFee(newFee);
        assertEq(market.borrowOpeningFee(), newFee);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.SetBorrowOpeningFee(newFee, newFee);
        vm.prank(OWNER);
        market.setBorrowOpeningFee(newFee);
        assertEq(market.borrowOpeningFee(), newFee);
    }
}
