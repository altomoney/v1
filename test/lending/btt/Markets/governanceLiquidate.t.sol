// SPDX-License-Identifier: UNLICENSED
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
        market.governanceLiquidate(USER);
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

    function test_RevertWhen_PositionIsSolvent() external givenSolventPosition {
        vm.startPrank(OWNER);
        market.governanceLiquidate(USER);
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

    modifier whenMarketIsNotPaused() {
        _;
    }

    modifier whenMarketIsPaused() {
        // Tag position before pausing, as tagging requires market to be unpaused
        vm.prank(TAGGER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);
        _;
    }

    function test_WhenPositionIsInsolvent() external givenPositionIsInsolvent whenMarketIsNotPaused {
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
        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(
            USER, OWNER, expectedCollateral, expectedBadDebt, expectedBadDebtShares
        );
        (uint256 collateralAmount, uint256 badDebtAmount) = market.governanceLiquidate(USER);
        IDcfDlbPriorityLiquidationEngine liquidationEngine =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        liquidationEngine.deleteLiquidablePosition(USER);
        vm.stopPrank();

        assertEq(collateralAmount, expectedCollateral);
        assertEq(badDebtAmount, expectedBadDebt);

        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore + expectedCollateral);

        Position memory positionAfter = market.position(USER);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(positionAfter.borrowShares, 0);

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

    function test_WhenPositionIsInsolventAndHasNoCollateral() external givenPositionIsInsolvent whenMarketIsNotPaused {
        vm.prank(TAGGER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);

        bytes32 collateralSlot = bytes32(uint256(keccak256(abi.encode(USER, uint256(8)))) + 1);
        vm.store(address(market), collateralSlot, bytes32(0));

        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();
        Position memory positionBefore = market.position(USER);
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);

        assertEq(positionBefore.collateralAssets, 0);

        uint256 expectedCollateral = 0;
        uint256 expectedBadDebt = Math.min(
            uint256(positionBefore.borrowShares)
                .convertToAssetsUp(totalBorrowedBefore.assets, totalBorrowedBefore.shares),
            totalBorrowedBefore.assets
        );
        uint128 expectedBadDebtShares = positionBefore.borrowShares;

        vm.startPrank(OWNER);
        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(
            USER, OWNER, expectedCollateral, expectedBadDebt, expectedBadDebtShares
        );
        (uint256 collateralAmount, uint256 badDebtAmount) = market.governanceLiquidate(USER);
        IDcfDlbPriorityLiquidationEngine liquidationEngine =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        liquidationEngine.deleteLiquidablePosition(USER);
        vm.stopPrank();

        assertEq(collateralAmount, expectedCollateral);
        assertEq(badDebtAmount, expectedBadDebt);

        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore);

        Position memory positionAfter = market.position(USER);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(positionAfter.borrowShares, 0);

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

    function test_WhenPositionIsInsolventAndMarketIsPaused() external givenPositionIsInsolvent whenMarketIsPaused {
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

        vm.startPrank(OWNER);
        vm.recordLogs();
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(
            USER, OWNER, expectedCollateral, expectedBadDebt, expectedBadDebtShares
        );
        (uint256 collateralAmount, uint256 badDebtAmount) = market.governanceLiquidate(USER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).deleteLiquidablePosition(USER);
        vm.stopPrank();

        // it should not emit AccrueInterest event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }

        assertEq(collateralAmount, expectedCollateral);
        assertEq(badDebtAmount, expectedBadDebt);
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore + expectedCollateral);

        Position memory positionAfter = market.position(USER);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(positionAfter.borrowShares, 0);

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

    function test_WhenPositionIsInsolventAndHasNoCollateralAndMarketIsPaused()
        external
        givenPositionIsInsolvent
        whenMarketIsPaused
    {
        bytes32 collateralSlot = bytes32(uint256(keccak256(abi.encode(USER, uint256(8)))) + 1);
        vm.store(address(market), collateralSlot, bytes32(0));

        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();
        Position memory positionBefore = market.position(USER);
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);

        assertEq(positionBefore.collateralAssets, 0);

        uint256 expectedCollateral = 0;
        uint256 expectedBadDebt = Math.min(
            uint256(positionBefore.borrowShares)
                .convertToAssetsUp(totalBorrowedBefore.assets, totalBorrowedBefore.shares),
            totalBorrowedBefore.assets
        );
        uint128 expectedBadDebtShares = positionBefore.borrowShares;

        vm.startPrank(OWNER);
        vm.recordLogs();
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(
            USER, OWNER, expectedCollateral, expectedBadDebt, expectedBadDebtShares
        );
        (uint256 collateralAmount, uint256 badDebtAmount) = market.governanceLiquidate(USER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).deleteLiquidablePosition(USER);
        vm.stopPrank();

        // it should not emit AccrueInterest event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }

        assertEq(collateralAmount, expectedCollateral);
        assertEq(badDebtAmount, expectedBadDebt);
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore);

        Position memory positionAfter = market.position(USER);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(positionAfter.borrowShares, 0);

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
}

