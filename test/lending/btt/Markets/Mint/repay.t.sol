// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {AltoMarketRepay} from "../repay.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketEvents, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

contract RepayTestMint is AltoMarketRepay {
    using AssetShareConversionMath for uint256;

    AltoMintMarket internal mintMarket;

    constructor() AltoMarketRepay(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    modifier givenClaimableFeesAssetsIsGreaterThanZero() {
        // Generate claimable fees by borrowing and accruing interest
        deal(address(collateralToken), address(this), 100 ether);
        market.addCollateral(100 ether, USER);

        vm.prank(OWNER);
        mintMarket.setDebtCeiling(100 ether);

        mintMarket.borrow(70 ether, 0, USER, USER, "");

        vm.warp(block.timestamp + 365 days);
        market.accrueInterest();
        _;
    }

    modifier givenClaimableFeesAssetsIsZero() {
        // Setup without generating fees
        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), INITIAL_SUPPLY);
        vm.prank(OWNER);
        mintMarket.setDebtCeiling(INITIAL_SUPPLY);

        market.addCollateral(10 ether, USER);
        market.borrow(5 ether, 0, USER, USER, "");
        _;
    }

    function test_GivenClaimableFeesAssetsIsGreaterThanZero_ShouldClaimInterestBeforeRepay()
        external
        givenClaimableFeesAssetsIsGreaterThanZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        assertGt(claimableFeesBefore, 0, "claimableFeesAssets should be greater than zero");

        uint256 repayAmount = 5 ether;
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        uint256 sharesToRepay = repayAmount.convertToSharesDown(totalBorrowedBefore.assets, totalBorrowedBefore.shares);

        deal(address(borrowToken), USER, repayAmount);
        vm.startPrank(USER);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore);

        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.Repay(USER, USER, repayAmount, sharesToRepay);

        market.repay(repayAmount, 0, USER);
        vm.stopPrank();

        assertEq(
            borrowToken.balanceOf(FEE_RECIPIENT),
            feeRecipientBalanceBefore + claimableFeesBefore,
            "Fee recipient should receive claimed interest"
        );
    }

    function test_GivenClaimableFeesAssetsIsZero_ShouldNotClaimInterest() external givenClaimableFeesAssetsIsZero {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        assertEq(claimableFeesBefore, 0, "claimableFeesAssets should be zero");

        deal(address(borrowToken), USER, 5 ether);
        vm.startPrank(USER);

        vm.recordLogs();
        market.repay(5 ether, 0, USER);
        vm.stopPrank();

        // Get recorded logs and verify no InterestClaimed event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == AltoMintMarket.InterestClaimed.selector) {
                revert("InterestClaimed event should not be emitted when claimableFeesAssets is zero");
            }
        }

        uint256 feeRecipientBalanceAfter = borrowToken.balanceOf(FEE_RECIPIENT);
        assertEq(
            feeRecipientBalanceAfter, feeRecipientBalanceBefore, "Fee recipient should not receive unclaimed interest"
        );
    }
}
