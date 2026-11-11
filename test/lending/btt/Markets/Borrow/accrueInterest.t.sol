// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IAltoBorrowMarketEvents} from "@alto/lending/interfaces/IAltoBorrowMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

contract AccrueInterestTestBorrow is MarketCommon {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    AltoBorrowMarket public borrowMarket;

    constructor() MarketCommon(MarketType.BORROW) {}

    function setUp() public override {
        super.setUp();
        borrowMarket = AltoBorrowMarket(address(market));
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

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // should do nothing
        market.accrueInterest();

        assertEq(entries.length, 0);
        assertEq(market.totalSupply().assets, totalSupplyBefore);
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore);
    }

    modifier whenIrmIsNotZeroAddress() {
        deal(address(collateralToken), address(this), 1 ether);
        deal(address(borrowToken), address(this), 1 ether);
        market.addSupply(0.5 ether, 0, SUPPLIER);
        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, hex"");
        _;
    }

    function test_WhenInterestIsZero_SameBlock() external whenMarketIsNotPaused whenIrmIsNotZeroAddress {
        // First call to accrue interest
        vm.warp(block.timestamp + 100 days);
        market.accrueInterest();

        // Record state after first accrual
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 feeRecipientSupplySharesBefore = market.position(FEE_RECIPIENT).supplyShares;

        // Second call in same block - should do nothing and not emit AccrueInterest event
        vm.recordLogs();
        market.accrueInterest();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // it should do nothing and not emit AccrueInterest event
        bytes32 accrueInterestSelector = IMarketEvents.AccrueInterest.selector;
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != accrueInterestSelector, "AccrueInterest event should not be emitted");
        }

        assertEq(market.totalSupply().assets, totalSupplyAssetsBefore, "totalSupply.assets unchanged");
        assertEq(market.totalSupply().shares, totalSupplySharesBefore, "totalSupply.shares unchanged");
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore, "totalBorrowed.assets unchanged");
        assertEq(
            market.position(FEE_RECIPIENT).supplyShares,
            feeRecipientSupplySharesBefore,
            "feeRecipient supplyShares unchanged"
        );
    }

    modifier whenInterestIsNonZero() {
        vm.warp(block.timestamp + 100 days);
        _;
    }

    function test_WhenInterestFeeIsZero() external whenMarketIsNotPaused whenIrmIsNotZeroAddress whenInterestIsNonZero {
        // Ensure interestFee is zero, skip accrue to not interfere with test
        vm.prank(OWNER);
        borrowMarket.setInterestFee(0, true);

        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 feeRecipientSupplySharesBefore = market.position(FEE_RECIPIENT).supplyShares;

        uint256 expectedInterest;
        uint256 expectedBorrowRate;

        vm.startPrank(address(market));
        uint256 snapshot = vm.snapshotState();
        (expectedInterest, expectedBorrowRate) =
            IIrm(market.irm()).updateInterestRate(totalSupplyAssetsBefore, totalBorrowedBefore);
        vm.revertToState(snapshot);
        vm.stopPrank();

        vm.expectEmit();
        emit IMarketEvents.AccrueInterest(
            expectedBorrowRate,
            expectedInterest,
            uint128(totalBorrowedBefore + expectedInterest),
            uint128(totalSupplyAssetsBefore + expectedInterest)
        );

        market.accrueInterest();

        assertEq(market.totalSupply().assets, totalSupplyAssetsBefore + expectedInterest);
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore + expectedInterest);

        assertEq(market.totalSupply().shares, totalSupplySharesBefore);
        assertEq(market.position(FEE_RECIPIENT).supplyShares, feeRecipientSupplySharesBefore);
    }

    function test_WhenInterestFeeIsNonZero()
        external
        whenMarketIsNotPaused
        whenIrmIsNotZeroAddress
        whenInterestIsNonZero
    {
        // Set interestFee to 10% (0.1 * MATH_PRECISION), skip accrue to not interfere with test
        uint256 interestFee = 0.1 ether; // 10% in MATH_PRECISION
        vm.prank(OWNER);
        borrowMarket.setInterestFee(interestFee, true);

        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 feeRecipientSupplySharesBefore = market.position(FEE_RECIPIENT).supplyShares;

        uint256 expectedInterest;
        uint256 expectedBorrowRate;

        vm.startPrank(address(market));
        uint256 snapshot = vm.snapshotState();
        (expectedInterest, expectedBorrowRate) =
            IIrm(market.irm()).updateInterestRate(totalSupplyAssetsBefore, totalBorrowedBefore);
        vm.revertToState(snapshot);
        vm.stopPrank();

        // Calculate expected feeAmount and feeShares
        uint256 expectedFeeAmount = expectedInterest.multiplyWithPrecision(interestFee);
        uint256 expectedFeeShares = expectedFeeAmount.convertToSharesDown(
            totalSupplyAssetsBefore + expectedInterest - expectedFeeAmount, totalSupplySharesBefore
        );

        vm.expectEmit(true, true, true, true);
        emit IAltoBorrowMarketEvents.InterestFeeAccrued(FEE_RECIPIENT, expectedInterest, expectedFeeShares);

        vm.expectEmit();
        emit IMarketEvents.AccrueInterest(
            expectedBorrowRate,
            expectedInterest,
            uint128(totalBorrowedBefore + expectedInterest),
            uint128(totalSupplyAssetsBefore + expectedInterest)
        );

        market.accrueInterest();

        assertEq(market.totalSupply().assets, totalSupplyAssetsBefore + expectedInterest);
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore + expectedInterest);

        assertEq(
            market.position(FEE_RECIPIENT).supplyShares,
            feeRecipientSupplySharesBefore + expectedFeeShares,
            "feeRecipient supplyShares"
        );

        assertEq(market.totalSupply().shares, totalSupplySharesBefore + expectedFeeShares, "totalSupply shares");
    }
}
