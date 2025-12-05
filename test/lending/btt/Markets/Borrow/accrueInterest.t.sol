// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
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
        vm.warp(block.timestamp + 100 days);
        _;
    }

    function test_WhenInterestFeeIsZero() external whenMarketIsNotPaused whenIrmIsNotZeroAddress {
        // Ensure interestFee is zero
        vm.prank(OWNER);
        borrowMarket.setInterestFee(0);

        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 feeRecipientSupplySharesBefore = market.position(FEE_RECIPIENT).supplyShares;

        uint256 expectedInterest;
        uint256 expectedBorrowRate;

        vm.startPrank(address(market));
        uint256 snapshot = vm.snapshot();
        (expectedInterest, expectedBorrowRate) =
            IIrm(market.irm()).updateInterestRate(totalSupplyAssetsBefore, totalBorrowedBefore);
        vm.revertTo(snapshot);
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

    function test_WhenInterestFeeIsNonZero() external whenMarketIsNotPaused whenIrmIsNotZeroAddress {
        // Set interestFee to 10% (0.1 * MATH_PRECISION)
        uint256 interestFee = 0.1 ether; // 10% in MATH_PRECISION
        vm.prank(OWNER);
        borrowMarket.setInterestFee(interestFee);

        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedBefore = market.totalBorrowed().assets;
        uint256 feeRecipientSupplySharesBefore = market.position(FEE_RECIPIENT).supplyShares;

        uint256 expectedInterest;
        uint256 expectedBorrowRate;

        vm.startPrank(address(market));
        uint256 snapshot = vm.snapshot();
        (expectedInterest, expectedBorrowRate) =
            IIrm(market.irm()).updateInterestRate(totalSupplyAssetsBefore, totalBorrowedBefore);
        vm.revertTo(snapshot);
        vm.stopPrank();

        // Calculate expected feeAmount and feeShares
        uint256 expectedFeeAmount = expectedInterest.multiplyWithPrecision(interestFee);
        uint256 expectedFeeShares = expectedFeeAmount.convertToSharesDown(
            totalSupplyAssetsBefore + expectedInterest - expectedFeeAmount, totalSupplySharesBefore
        );

        vm.expectEmit(true, true, true, true);
        emit AltoBorrowMarket.InterestFeeAccrued(FEE_RECIPIENT, expectedInterest, expectedFeeShares);

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
