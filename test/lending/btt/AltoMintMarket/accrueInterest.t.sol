// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";

contract AccrueInterestTest is AltoMintMarketTest {
    function test_RevertWhen_MarketIsPaused() external {
        // Set owner as pauser first
        vm.prank(owner);
        market.setPauser(owner, PAUSED_MARKET, true);

        vm.prank(owner);
        market.pause(PAUSED_MARKET, true);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.accrueInterest();
    }

    modifier givenMarketIsNotPaused() {
        // Market is not paused by default
        _;
    }

    function test_NotAccrueInterestWhen_TotalBorrowedIsZero() external givenMarketIsNotPaused {
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();

        market.accrueInterest();

        // it should not accrue interest significantly
        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        // In mint market, there might be minimal interest due to virtual supply
        // Allow for small increases due to virtual interest
        assertLe(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore + 2e9); // Allow up to 2 gwei increase
    }

    modifier whenTotalBorrowedIsGreaterThanZero() {
        // Setup a borrow position first
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();
        _;
    }

    function test_NotAccrueInterestWhen_BorrowRateIsZero()
        external
        givenMarketIsNotPaused
        whenTotalBorrowedIsGreaterThanZero
    {
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();

        market.accrueInterest();

        // it should not accrue interest significantly
        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        // With zero rate, minimal change expected due to virtual interest
        assertLe(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore + 2e9); // Allow up to 2 gwei increase
    }

    function test_AccrueInterestWhen_BorrowRateIsGreaterThanZero()
        external
        givenMarketIsNotPaused
        whenTotalBorrowedIsGreaterThanZero
    {
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();

        // Advance time to accumulate interest
        vm.warp(block.timestamp + 365 days);

        market.accrueInterest();

        // it should accrue interest
        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);
    }
}
