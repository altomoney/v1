// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {AltoBorrowMarketliquidate} from "../liquidate.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract MintTestLiquidate is AltoBorrowMarketliquidate {
    AltoMintMarket internal mintMarket;

    constructor() AltoBorrowMarketliquidate(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    modifier givenClaimableFeesAssetsIsGreaterThanZero() {
        // After givenPositionIsInsolvent sets up the position, we need to ensure there are claimable fees
        // The position is already set up, so we accrue interest to generate claimable fees
        // Note: givenPositionIsInsolvent already warps time by 100 days, so we accrue interest here
        market.accrueInterest();
        _;
    }

    modifier givenClaimableFeesAssetsIsZero() {
        // Accrue interest to reset the IRM timestamp, so liquidate's internal _accrueInterest() yields 0
        market.accrueInterest();
        // Claim all generated fees to reset claimableFeesAssets to 0
        uint256 fees = mintMarket.claimableFeesAssets();
        if (fees > 0) {
            vm.prank(OWNER);
            mintMarket.claimInterest(0);
        }
        _;
    }

    function test_GivenClaimableFeesAssetsIsGreaterThanZero_ShouldClaimInterestBeforeLiquidate()
        external
        givenPositionIsInsolvent
        givenClaimableFeesAssetsIsGreaterThanZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        assertGt(claimableFeesBefore, 0, "claimableFeesAssets should be greater than zero");

        // Set up priority liquidator
        vm.startPrank(OWNER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
        vm.stopPrank();

        deal(address(borrowToken), PRIORITY_LIQUIDATOR, 1 ether);
        vm.startPrank(PRIORITY_LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore);

        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, PRIORITY_LIQUIDATOR, 0, 0, 0, 0, 0, 0);

        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
        vm.stopPrank();

        assertEq(
            borrowToken.balanceOf(FEE_RECIPIENT),
            feeRecipientBalanceBefore + claimableFeesBefore,
            "Fee recipient should receive claimed interest"
        );

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    function test_GivenClaimableFeesAssetsIsZero_ShouldNotClaimInterest()
        external
        givenPositionIsInsolvent
        givenClaimableFeesAssetsIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        assertEq(claimableFeesBefore, 0, "claimableFeesAssets should be zero");

        vm.startPrank(OWNER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
        vm.stopPrank();

        deal(address(borrowToken), PRIORITY_LIQUIDATOR, 1 ether);
        vm.startPrank(PRIORITY_LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // Record logs to verify no InterestClaimed event is emitted
        vm.recordLogs();
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, PRIORITY_LIQUIDATOR, 0, 0, 0, 0, 0, 0);

        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
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

        // Verify liquidation proceeded correctly
        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }
}
