// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IMarketErrors, IMarketEvents, Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration,
    LiquidablePosition
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";

contract AltoBorrowMarketGovernanceLiquidate is MarketCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    address internal immutable TAGGER = makeAddr("Tagger");

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.governanceLiquidate(USER, false);
    }

    modifier givenSolventPosition() {
        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), 100 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(100 ether, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(100 ether);
            vm.stopPrank();
        }

        market.addCollateral(2 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, "");
        _;
    }

    function test_GivenPositionIsSolvent() external givenSolventPosition {
        vm.startPrank(OWNER);
        market.governanceLiquidate(USER, false);
        vm.stopPrank();
    }

    modifier givenPositionIsInsolvent() {
        vm.startPrank(OWNER);
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))), false);
        vm.stopPrank();

        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), 100 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(100 ether, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(100 ether);
            vm.stopPrank();
        }

        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, "");

        vm.warp(block.timestamp + 100 days);
        _;
    }

    // ==================== AccrueInterest emission tests ====================

    function test_WhenMarketIsNotPausedAndSkipAccrueInterestIsFalse_ShouldEmitAccrueInterest()
        external
        givenPositionIsInsolvent
    {
        vm.startPrank(OWNER);
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        market.governanceLiquidate(USER, false);
        vm.stopPrank();
    }

    function test_WhenMarketIsPaused_ShouldNotEmitAccrueInterest() external givenPositionIsInsolvent {
        vm.prank(TAGGER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        vm.startPrank(OWNER);
        vm.recordLogs();
        market.governanceLiquidate(USER, false);
        vm.stopPrank();

        _assertNoAccrueInterestEvent();
    }

    function test_WhenSkipAccrueInterestIsTrue_ShouldNotEmitAccrueInterest() external givenPositionIsInsolvent {
        vm.startPrank(OWNER);
        vm.recordLogs();
        market.governanceLiquidate(USER, true);
        vm.stopPrank();

        _assertNoAccrueInterestEvent();
    }

    function test_WhenMarketIsPausedAndSkipAccrueInterestIsTrue_ShouldNotEmitAccrueInterest()
        external
        givenPositionIsInsolvent
    {
        vm.prank(TAGGER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        vm.startPrank(OWNER);
        vm.recordLogs();
        market.governanceLiquidate(USER, true);
        vm.stopPrank();

        _assertNoAccrueInterestEvent();
    }

    // ==================== Liquidation behavior tests ====================

    function test_WhenPositionIsTagged() external givenPositionIsInsolvent {
        vm.prank(TAGGER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);

        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();
        Position memory positionBefore = market.position(USER);
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);

        uint256 expectedCollateral = positionBefore.collateralAssets;
        uint256 expectedBadDebt = Math.min(
            uint256(positionBefore.borrowShares)
                .convertToAssetsUp(totalBorrowedBefore.assets, totalBorrowedBefore.shares),
            totalBorrowedBefore.assets
        );
        uint128 expectedBadDebtShares = positionBefore.borrowShares;

        LiquidablePosition memory liquidableBefore =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidablePositions(USER);
        assertTrue(liquidableBefore.tagged);

        vm.startPrank(OWNER);
        // it should emit GovernanceLiquidation
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(
            USER, OWNER, expectedCollateral, expectedBadDebt, expectedBadDebtShares
        );
        (uint256 collateralAmount, uint256 badDebtAmount) = market.governanceLiquidate(USER, false);
        // it should delete liquidable position
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).deleteLiquidablePosition(USER);
        vm.stopPrank();

        // it should return collateral amount and bad debt amount
        assertEq(collateralAmount, expectedCollateral);
        assertEq(badDebtAmount, expectedBadDebt);

        // it should transfer collateral tokens to owner
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore + expectedCollateral);

        Position memory positionAfter = market.position(USER);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(positionAfter.borrowShares, 0);

        // it should apply bad debt to market
        Balance memory totalBorrowedAfter = market.totalBorrowed();
        assertEq(totalBorrowedAfter.assets, totalBorrowedBefore.assets - badDebtAmount);
        assertEq(totalBorrowedAfter.shares, totalBorrowedBefore.shares - expectedBadDebtShares);

        Balance memory totalSupplyAfter = market.totalSupply();
        if (marketType == MarketType.BORROW) {
            assertEq(totalSupplyAfter.assets, totalSupplyBefore.assets - badDebtAmount);
            assertEq(totalSupplyAfter.shares, totalSupplyBefore.shares);
        } else {
            assertEq(totalSupplyAfter.assets, totalSupplyBefore.assets);
            assertEq(totalSupplyAfter.shares, totalSupplyBefore.shares);
        }

        LiquidablePosition memory liquidableAfter =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidablePositions(USER);
        assertFalse(liquidableAfter.tagged);
        assertEq(liquidableAfter.tagger, address(0));
        assertEq(liquidableAfter.timestamp, 0);
    }

    function test_WhenBorrowerHasNoCollateralRemaining() external givenPositionIsInsolvent {
        vm.prank(TAGGER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);

        // Set collateral to zero
        bytes32 collateralSlot = bytes32(uint256(keccak256(abi.encode(USER, uint256(8)))) + 1);
        vm.store(address(market), collateralSlot, bytes32(0));

        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();
        Position memory positionBefore = market.position(USER);
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);

        assertEq(positionBefore.collateralAssets, 0);

        uint256 expectedBadDebt = Math.min(
            uint256(positionBefore.borrowShares)
                .convertToAssetsUp(totalBorrowedBefore.assets, totalBorrowedBefore.shares),
            totalBorrowedBefore.assets
        );
        uint128 expectedBadDebtShares = positionBefore.borrowShares;

        vm.startPrank(OWNER);
        // it should emit GovernanceLiquidation with zero collateral
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(USER, OWNER, 0, expectedBadDebt, expectedBadDebtShares);
        (uint256 collateralAmount, uint256 badDebtAmount) = market.governanceLiquidate(USER, false);
        // it should delete liquidable position
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).deleteLiquidablePosition(USER);
        vm.stopPrank();

        // it should return collateral amount and bad debt amount
        assertEq(collateralAmount, 0);
        assertEq(badDebtAmount, expectedBadDebt);

        // it should not transfer collateral tokens to owner
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore);

        Position memory positionAfter = market.position(USER);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(positionAfter.borrowShares, 0);

        // it should apply bad debt to market
        Balance memory totalBorrowedAfter = market.totalBorrowed();
        assertEq(totalBorrowedAfter.assets, totalBorrowedBefore.assets - badDebtAmount);
        assertEq(totalBorrowedAfter.shares, totalBorrowedBefore.shares - expectedBadDebtShares);

        Balance memory totalSupplyAfter = market.totalSupply();
        if (marketType == MarketType.BORROW) {
            assertEq(totalSupplyAfter.assets, totalSupplyBefore.assets - badDebtAmount);
            assertEq(totalSupplyAfter.shares, totalSupplyBefore.shares);
        } else {
            assertEq(totalSupplyAfter.assets, totalSupplyBefore.assets);
            assertEq(totalSupplyAfter.shares, totalSupplyBefore.shares);
        }

        LiquidablePosition memory liquidableAfter =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidablePositions(USER);
        assertFalse(liquidableAfter.tagged);
        assertEq(liquidableAfter.tagger, address(0));
        assertEq(liquidableAfter.timestamp, 0);
    }

    // ==================== Helper functions ====================

    function _assertNoAccrueInterestEvent() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }
    }
}
