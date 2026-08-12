// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {DusdPegCurveOracleCommon} from "./DusdPegCurveOracleCommon.t.sol";

contract DusdPegCurveOracleGetPriceTest is DusdPegCurveOracleCommon {
    function test_RevertWhen_MaLastTimeReverts() external {
        _mockPoolReadRevert(_maLastTimeCall());

        _expectPoolReadRevert();
        oracle.getPrice();
    }

    function test_WhenPriceTimestampIsZero() external {
        _mockTimestamps(0, 17);
        _armRuntimeAndPriceReadsToRevert();

        _assertPriceResult(0, 0, false);
    }

    function test_WhenPriceTimestampIsInTheFuture() external {
        _mockTimestamps(block.timestamp + 1, 17);
        _armRuntimeAndPriceReadsToRevert();

        _assertPriceResult(0, 0, false);
    }

    function test_WhenPriceTimestampExceedsUint48() external {
        uint256 observedAt = uint256(type(uint48).max) + 1;
        vm.warp(observedAt + 1);
        _mockTimestamps(observedAt, 17);
        _armRuntimeAndPriceReadsToRevert();

        _assertPriceResult(0, 0, false);
    }

    function test_WhenPriceTimestampEqualsBlockTimestamp() external {
        uint256 price = 0.99 ether;
        _mockTimestamps(block.timestamp, 17);
        _mockPrice(price);

        _assertPriceResult(price, uint48(block.timestamp), true);
    }

    function test_WhenPriceTimestampEqualsUint48Max() external {
        vm.warp(type(uint48).max);
        _mockTimestamps(type(uint48).max, 17);
        _mockPrice(PRICE_WAD);

        _assertPriceResult(PRICE_WAD, type(uint48).max, true);
    }

    function test_WhenPriceTimestampIsArbitrarilyOld() external {
        uint48 observedAt = 1;
        vm.warp(DEFAULT_NOW + 365 days);
        _mockTimestamps(observedAt, 17);
        _mockPrice(PRICE_WAD);

        _assertPriceResult(PRICE_WAD, observedAt, true);
    }

    function test_WhenOnlyInvariantTimestampChanges() external {
        uint48 observedAt = uint48(block.timestamp);
        _mockTimestamps(observedAt, 1);
        _mockPrice(PRICE_WAD);

        (uint256 firstPrice, uint48 firstObservedAt, bool firstValid) = oracle.getPrice();
        assertEq(firstPrice, PRICE_WAD);
        assertEq(firstObservedAt, observedAt);
        assertTrue(firstValid);

        vm.clearMockedCalls();
        _mockTimestamps(observedAt, type(uint128).max);
        _mockPrice(PRICE_WAD);
        (uint256 secondPrice, uint48 secondObservedAt, bool secondValid) = oracle.getPrice();

        assertEq(secondPrice, PRICE_WAD);
        assertEq(secondObservedAt, observedAt);
        assertTrue(secondValid);
    }

    function test_RevertWhen_RuntimeMaExpTimeReadReverts() external {
        _mockValidTimestamp();
        _mockPoolReadRevert(_maExpTimeCall());

        _expectPoolReadRevert();
        oracle.getPrice();
    }

    function test_WhenRuntimeMaExpTimeMismatches() external {
        _mockValidTimestamp();
        _mockPoolReturn(_maExpTimeCall(), MA_EXP_TIME + 1);
        _mockPoolReadRevert(_aPreciseCall());
        _mockPoolReadRevert(_futureACall());
        _mockPoolReadRevert(_priceOracleCall());

        _assertPriceResult(0, uint48(block.timestamp), false);
    }

    function test_RevertWhen_RuntimeAPreciseReadReverts() external {
        _mockValidTimestamp();
        _mockPoolReturn(_maExpTimeCall(), MA_EXP_TIME);
        _mockPoolReadRevert(_aPreciseCall());

        _expectPoolReadRevert();
        oracle.getPrice();
    }

    function test_WhenRuntimeAPreciseMismatches() external {
        _mockValidTimestamp();
        _mockPoolReturn(_maExpTimeCall(), MA_EXP_TIME);
        _mockPoolReturn(_aPreciseCall(), A_PRECISE + 1);
        _mockPoolReadRevert(_futureACall());
        _mockPoolReadRevert(_priceOracleCall());

        _assertPriceResult(0, uint48(block.timestamp), false);
    }

    function test_RevertWhen_RuntimeFutureAReadReverts() external {
        _mockValidTimestamp();
        _mockPoolReturn(_maExpTimeCall(), MA_EXP_TIME);
        _mockPoolReturn(_aPreciseCall(), A_PRECISE);
        _mockPoolReadRevert(_futureACall());

        _expectPoolReadRevert();
        oracle.getPrice();
    }

    function test_WhenRuntimeFutureAMismatches() external {
        _mockValidTimestamp();
        _mockPoolReturn(_maExpTimeCall(), MA_EXP_TIME);
        _mockPoolReturn(_aPreciseCall(), A_PRECISE);
        _mockPoolReturn(_futureACall(), A_PRECISE + 1);
        _mockPoolReadRevert(_priceOracleCall());

        _assertPriceResult(0, uint48(block.timestamp), false);
    }

    function test_WhenAllRuntimeValuesMatch_ItReadsThePrice() external {
        _mockValidTimestamp();
        _mockController(MA_EXP_TIME, A_PRECISE, A_PRECISE);
        _mockPrice(PRICE_WAD);
        vm.expectCall(address(pool), _priceOracleCall(), 1);

        _assertPriceResult(PRICE_WAD, uint48(block.timestamp), true);
    }

    function test_RevertWhen_PriceOracleReverts() external {
        _mockValidTimestamp();
        _mockPoolReadRevert(_priceOracleCall());

        _expectPoolReadRevert();
        oracle.getPrice();
    }

    function test_WhenPriceOracleReturnsZero() external {
        _mockValidTimestamp();
        _mockPrice(0);

        _assertPriceResult(0, uint48(block.timestamp), false);
    }

    function test_WhenPriceOracleReturnsANonZeroPriceBelowPeg() external {
        uint256 price = 0.73 ether;
        _mockValidTimestamp();
        _mockPrice(price);
        vm.expectCall(address(pool), _priceOracleCall(), 1);

        _assertPriceResult(price, uint48(block.timestamp), true);
    }

    function test_WhenPriceOracleReturnsUint256Max() external {
        _mockValidTimestamp();
        _mockPrice(type(uint256).max);

        _assertPriceResult(type(uint256).max, uint48(block.timestamp), true);
    }

    function test_WhenExecutionSucceeds_ItDoesNotModifyStateOrEmitEvents() external {
        _mockValidTimestamp();
        _mockPrice(PRICE_WAD);
        address ownerBefore = oracle.owner();
        address pendingOwnerBefore = oracle.pendingOwner();
        (uint256 expectedMaExpTimeBefore, uint256 expectedAPreciseBefore) = oracle.runtimeConfig();

        vm.recordLogs();
        oracle.getPrice();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(oracle.owner(), ownerBefore);
        assertEq(oracle.pendingOwner(), pendingOwnerBefore);
        _assertRuntimeConfig(oracle, expectedMaExpTimeBefore, expectedAPreciseBefore);
        assertEq(logs.length, 0);
    }

    function _mockValidTimestamp() private {
        _mockTimestamps(block.timestamp, block.timestamp);
    }

    function _mockTimestamps(uint256 priceTimestamp, uint256 invariantTimestamp) private {
        uint256 packed = priceTimestamp | (invariantTimestamp << 128);
        _mockPoolReturn(_maLastTimeCall(), packed);
    }

    function _mockController(uint256 maExpTime, uint256 aPrecise, uint256 futureA) private {
        _mockPoolReturn(_maExpTimeCall(), maExpTime);
        _mockPoolReturn(_aPreciseCall(), aPrecise);
        _mockPoolReturn(_futureACall(), futureA);
    }

    function _mockPrice(uint256 price) private {
        _mockPoolReturn(_priceOracleCall(), price);
    }

    function _armRuntimeAndPriceReadsToRevert() private {
        _mockPoolReadRevert(_maExpTimeCall());
        _mockPoolReadRevert(_aPreciseCall());
        _mockPoolReadRevert(_futureACall());
        _mockPoolReadRevert(_priceOracleCall());
    }
}
