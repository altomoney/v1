// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract AccrueInterestTestMint is MarketCommon {
    constructor() MarketCommon(MarketType.MINT) {}

    AltoMintMarket internal mintMarket;

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

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
        uint256 claimableFeesAssetsBefore = mintMarket.claimableFeesAssets();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // should do nothing
        market.accrueInterest();

        assertEq(entries.length, 0);
        assertEq(market.totalSupply().assets, totalSupplyBefore);
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesAssetsBefore);
    }

    modifier whenIrmIsNotZeroAddress() {
        deal(address(collateralToken), address(this), 1 ether);
        deal(address(borrowToken), address(this), 1 ether);
        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, hex"");
        _;
    }

    function test_WhenInterestIsZero_SameBlock() external whenMarketIsNotPaused whenIrmIsNotZeroAddress {
        // First call to accrue interest
        vm.warp(block.timestamp + 100 days);
        market.accrueInterest();

        // Record state after first accrual
        uint256 totalSupplyBefore = market.totalSupply().assets;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 claimableFeesAssetsBefore = mintMarket.claimableFeesAssets();

        // Second call in same block - should do nothing and not emit AccrueInterest event
        vm.recordLogs();
        market.accrueInterest();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // it should do nothing and not emit AccrueInterest event
        bytes32 accrueInterestSelector = IMarketEvents.AccrueInterest.selector;
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != accrueInterestSelector, "AccrueInterest event should not be emitted");
        }

        assertEq(market.totalSupply().assets, totalSupplyBefore, "totalSupply.assets unchanged");
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore, "totalBorrowed.assets unchanged");
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesAssetsBefore, "claimableFeesAssets unchanged");
    }

    modifier whenInterestIsNonZero() {
        vm.warp(block.timestamp + 100 days);
        _;
    }

    function test_WhenInterestIsNonZero() external whenMarketIsNotPaused whenIrmIsNotZeroAddress whenInterestIsNonZero {
        uint256 totalSupplyBefore = market.totalSupply().assets;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 claimableFeesAssetsBefore = mintMarket.claimableFeesAssets();

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
            uint128(totalSupplyBefore)
        );

        market.accrueInterest();

        // it should not update totalSupply.assets
        assertEq(market.totalSupply().assets, totalSupplyBefore);
        // it should update totalBorrowed.assets and claimableFeesAssets
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore + expectedInterest);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesAssetsBefore + expectedInterest);
    }
}
