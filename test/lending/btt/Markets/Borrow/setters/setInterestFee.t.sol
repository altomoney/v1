// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {Vm} from "forge-std/Vm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

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
        borrowMarket.setInterestFee(0.1 ether, false);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    modifier whenMarketIsPaused() {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);
        _;
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldInterestFee = borrowMarket.interestFee();
        uint256 newInterestFee = oldInterestFee + 1;

        // it should emit accrue event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);

        // it should emit SetInterestFee event
        vm.expectEmit();
        emit AltoBorrowMarket.SetInterestFee(oldInterestFee, newInterestFee);

        borrowMarket.setInterestFee(newInterestFee, false);

        // it should update interestFee
        assertEq(borrowMarket.interestFee(), newInterestFee);
    }

    function test_WhenCallerIsOwnerAndMarketIsPaused() external whenMarketIsPaused whenCallerIsOwner {
        uint256 oldInterestFee = borrowMarket.interestFee();
        uint256 newInterestFee = oldInterestFee + 1;

        // it should emit SetInterestFee event
        vm.expectEmit();
        emit AltoBorrowMarket.SetInterestFee(oldInterestFee, newInterestFee);

        vm.recordLogs();
        borrowMarket.setInterestFee(newInterestFee, false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // it should not emit accrue event
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }

        // it should update interestFee
        assertEq(borrowMarket.interestFee(), newInterestFee);
    }

    function test_WhenCallerIsOwnerAndSkipAccrueInterest() external whenCallerIsOwner {
        uint256 oldInterestFee = borrowMarket.interestFee();
        uint256 newInterestFee = oldInterestFee + 1;

        // it should emit SetInterestFee event
        vm.expectEmit();
        emit AltoBorrowMarket.SetInterestFee(oldInterestFee, newInterestFee);

        vm.recordLogs();
        borrowMarket.setInterestFee(newInterestFee, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // it should not emit accrue event
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }

        // it should update interestFee
        assertEq(borrowMarket.interestFee(), newInterestFee);
    }

    function test_RevertWhen_InterestFeeIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setInterestFee(MATH_PRECISION + 1, false);
    }
}

