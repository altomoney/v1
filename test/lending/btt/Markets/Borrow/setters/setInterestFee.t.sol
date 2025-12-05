// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

contract SetInterestFeeTestBorrow is MarketCommon {
    AltoBorrowMarket public borrowMarket;

    constructor() MarketCommon(MarketType.BORROW) {}

    function setUp() public override {
        super.setUp();
        borrowMarket = AltoBorrowMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        borrowMarket.setInterestFee(0.1 ether);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldInterestFee = borrowMarket.interestFee();
        uint256 newInterestFee = oldInterestFee + 1;

        // it should emit SetInterestFee event
        vm.expectEmit();
        emit AltoBorrowMarket.SetInterestFee(oldInterestFee, newInterestFee);

        borrowMarket.setInterestFee(newInterestFee);

        // it should update interestFee
        assertEq(borrowMarket.interestFee(), newInterestFee);
    }

    function test_RevertWhen_InterestFeeIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setInterestFee(MATH_PRECISION + 1);
    }
}

