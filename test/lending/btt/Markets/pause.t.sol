// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {IMarketEvents, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract AltoMarketPause is MarketCommon {
    constructor(MarketType marketType) MarketCommon(marketType) {}

    modifier setUpMarket() {
        deal(address(borrowToken), address(this), 100 ether);
        deal(address(collateralToken), address(this), 100 ether);

        if (marketType == MarketType.BORROW) {
            market.addSupply(0.75 ether, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(0.75 ether);
        }
        market.addCollateral(1 ether, USER);
        market.borrow(0.75 ether, 0, USER, USER, hex"");

        _;
    }

    function test_WhenMarketIsPaused() external setUpMarket {
        vm.startPrank(PAUSER);

        vm.expectEmit();
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, true);

        market.pause(PAUSE_TYPE, true);

        vm.stopPrank();

        // it should not accrue any inerest as time passes
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();

        vm.warp(block.timestamp + 100 days);

        Balance memory totalBorrowedAfter = market.totalBorrowed();
        assertEq(totalBorrowedAfter.assets, totalBorrowedBefore.assets);
        assertEq(totalSupplyBefore.assets, totalSupplyBefore.assets);

        vm.startPrank(PAUSER);
        vm.expectEmit();
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, false);
        market.pause(PAUSE_TYPE, false);
        vm.stopPrank();

        market.accrueInterest();

        Balance memory totalBorrowedAfterUnpaused = market.totalBorrowed();
        Balance memory totalSupplyAfterUnpaused = market.totalSupply();
        assertEq(totalBorrowedAfterUnpaused.assets, totalBorrowedBefore.assets);
        assertEq(totalSupplyAfterUnpaused.assets, totalSupplyBefore.assets);

        vm.warp(block.timestamp + 100 days);

        market.accrueInterest();

        Balance memory totalBorrowedAfterUnpausedPostTimePassed = market.totalBorrowed();
        Balance memory totalSupplyAfterUnpausedPostTimePassed = market.totalSupply();
        assertGt(totalBorrowedAfterUnpausedPostTimePassed.assets, totalBorrowedBefore.assets);
        if (marketType == MarketType.BORROW) {
            assertGt(totalSupplyAfterUnpausedPostTimePassed.assets, totalSupplyBefore.assets);
        }
    }

    function test_WhenMarketIsUnpaused() external setUpMarket {
        // get accrued amounts if market was not paused
        uint256 TIME_TO_ACCRUE = 50 days;
        uint256 snapshot = vm.snapshot();
        vm.warp(block.timestamp + TIME_TO_ACCRUE);
        Balance memory totalBorrowedBeforeAccrued = market.totalBorrowed();
        Balance memory totalSupplyBeforeAccrued = market.totalSupply();
        vm.revertTo(snapshot);

        vm.startPrank(PAUSER);

        vm.expectEmit();
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, true);

        market.pause(PAUSE_TYPE, true);

        vm.stopPrank();

        vm.warp(block.timestamp + 100 days);

        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();

        vm.startPrank(PAUSER);
        vm.expectEmit();
        emit IPausable.Paused(PAUSER, PAUSE_TYPE, false);
        market.pause(PAUSE_TYPE, false);
        vm.stopPrank();

        market.accrueInterest();

        Balance memory totalBorrowedAfterUnpaused = market.totalBorrowed();
        Balance memory totalSupplyAfterUnpaused = market.totalSupply();
        assertEq(totalBorrowedAfterUnpaused.assets, totalBorrowedBefore.assets);
        assertEq(totalSupplyAfterUnpaused.assets, totalSupplyBefore.assets);

        vm.warp(block.timestamp + TIME_TO_ACCRUE);

        market.accrueInterest();

        Balance memory totalBorrowedAfterUnpausedPostTimePassed = market.totalBorrowed();
        Balance memory totalSupplyAfterUnpausedPostTimePassed = market.totalSupply();
        // it should restart interest accrual from current time
        assertGt(totalBorrowedAfterUnpausedPostTimePassed.assets, totalBorrowedBeforeAccrued.assets);
        if (marketType == MarketType.BORROW) {
            assertGt(totalSupplyAfterUnpausedPostTimePassed.assets, totalSupplyBeforeAccrued.assets);
        }
    }

    function test_RevertWhen_MarketIsAlreadyPausedAndPausedAgain() external {
        vm.startPrank(PAUSER);
        market.pause(PAUSE_TYPE, true);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, true, true));
        market.pause(PAUSE_TYPE, true);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsUnpausedAndUnpausedAgain() external {
        vm.startPrank(PAUSER);
        // it should revert (default state is false = unpaused)
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, false, false));
        market.pause(PAUSE_TYPE, false);
        vm.stopPrank();
    }
}
