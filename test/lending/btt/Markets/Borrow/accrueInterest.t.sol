// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract AccrueInterestTestBorrow is MarketCommon {
    constructor() MarketCommon(MarketType.BORROW) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.accrueInterest();
    }

    modifier whenMarketIsNotPaused() {
        _;
    }

    function test_WhenIrmIsZeroAddress() external whenMarketIsNotPaused {
        vm.prank(OWNER);
        market.setIrm(address(0), false);

        uint256 totalSupplyBefore = market.totalSupply().assets;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // should do nothing
        market.accrueInterest();

        assertEq(entries.length, 0);
        assertEq(market.totalSupply().assets, totalSupplyBefore);
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore);
    }

    function test_WhenIrmIsNotZeroAddress() external whenMarketIsNotPaused {
        deal(address(collateralToken), address(this), 1 ether);
        deal(address(borrowToken), address(this), 1 ether);
        market.addSupply(0.5 ether, 0, SUPPLIER);
        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, hex"");

        vm.warp(block.timestamp + 100 days);

        uint256 totalSupplyBefore = market.totalSupply().assets;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;

        uint256 expectedInterest;
        uint256 expectedBorrowRate;

        vm.startPrank(address(market));
        uint256 snapshot = vm.snapshot();
        (expectedInterest, expectedBorrowRate) =
            IIrm(market.irm()).updateInterestRate(totalSupplyBefore, totalBorrowedBefore);
        vm.revertTo(snapshot);
        vm.stopPrank();

        // it should emit AccrueInterest event
        vm.expectEmit();
        emit IMarketEvents.AccrueInterest(
            expectedBorrowRate,
            expectedInterest,
            uint128(totalBorrowedBefore + expectedInterest),
            uint128(totalSupplyBefore + expectedInterest)
        );

        // it should update totalSupply.assets and totalBorrowed.assets
        market.accrueInterest();

        assertEq(market.totalSupply().assets, totalSupplyBefore + expectedInterest);
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore + expectedInterest);
    }
}
