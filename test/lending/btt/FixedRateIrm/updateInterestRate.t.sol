// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {FixedRateIrmCommon} from "./FixedRateIrmCommon.t.sol";

contract FixedRateIrmUpdateInterestRateTest is FixedRateIrmCommon {
    function test_RevertWhen_CallerIsNotMarket_IncludingOwnerAndUnsetMarket() public {
        _expectUnauthorized(OWNER);
        _expectUnauthorized(OTHER);
        _assertState(INITIAL_RATE, 0);
        _bindMarket();
        _expectUnauthorized(OWNER);
        _expectUnauthorized(OTHER);
        _assertState(INITIAL_RATE, uint48(START));
    }

    function testFuzz_WhenAccruing_UsesStoredRateAndIgnoresTotalSupply(
        uint256 supply,
        uint256 debt,
        uint256 rate,
        uint256 elapsed
    ) public {
        debt = bound(debt, 0, 1e30);
        rate = bound(rate, 0, MAX_RATE);
        elapsed = bound(elapsed, 0, 5 * 365 days);
        irm = new FixedRateIrm(rate, OWNER);
        _bindMarket();
        vm.warp(START + elapsed);
        _updateAndAssert(supply, debt, _expectedInterest(debt, rate, elapsed), rate);
    }

    function test_WhenElapsedTimeIsZero_ReturnsZeroInterestAndEmits() public {
        _bindMarket();
        _updateAndAssert(1000 ether, 800 ether, 0, INITIAL_RATE);
    }

    function test_WhenBorrowedAmountIsZero_StillCheckpointsAndEmits() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _updateAndAssert(0, 0, 0, INITIAL_RATE);
    }

    function test_WhenRateIsZero_ReturnsZeroInterestAndAdvancesTimestamp() public {
        irm = new FixedRateIrm(0, OWNER);
        _bindMarket();
        vm.warp(START + 365 days);
        _updateAndAssert(0, 800 ether, 0, 0);
    }

    function test_WhenInterestIsBelowOneWei_RoundsDown() public {
        _bindMarket();
        vm.warp(START + 1);
        _updateAndAssert(0, 1, 0, INITIAL_RATE);
    }

    function test_WhenCompoundingCrossesQuarticThreshold_UsesExactRoundedInterest() public {
        uint256[2] memory elapsed = [uint256(200_000_000), uint256(200_000_001)];
        // Hand-calculated Taylor factors: 0.221333333333333333 at the
        // threshold and 0.221400001221333332 just above it, multiplied by 800.
        uint256[2] memory interest = [uint256(177_066_666_666_666_666_400), uint256(177_120_000_977_066_665_600)];
        for (uint256 i; i < elapsed.length; ++i) {
            vm.warp(START);
            irm = new FixedRateIrm(INITIAL_RATE, OWNER);
            _bindMarket();
            vm.warp(START + elapsed[i]);
            _updateAndAssert(0, 800 ether, interest[i], INITIAL_RATE);
        }
    }

    function test_WhenCompoundFactorReachesCap_LimitsInterestToOneHundredTimesDebt() public {
        _bindMarket();
        vm.warp(START + 500 * 365 days);
        _updateAndAssert(0, 800 ether, 80_000 ether, INITIAL_RATE);
    }

    function test_WhenCalledRepeatedly_AccruesOnlySinceLastCheckpoint() public {
        _bindMarket();
        vm.warp(START + 100_000);
        uint256 interest = _expectedInterest(800 ether, INITIAL_RATE, 100_000);
        _updateAndAssert(0, 800 ether, interest, INITIAL_RATE);
        _updateAndAssert(type(uint256).max, 800 ether, 0, INITIAL_RATE);
        vm.warp(START + 200_000);
        _updateAndAssert(0, 800 ether, interest, INITIAL_RATE);
    }

    function test_WhenTimestampIsZeroMaximumOrCrossesUint48_StoresLow48Bits() public {
        vm.warp(0);
        _bindMarket();
        _updateAndAssert(0, 800 ether, 0, INITIAL_RATE);

        uint256[3] memory timestamps = [uint256(type(uint48).max), uint256(1) << 48, (uint256(1) << 48) + 37];
        for (uint256 i; i < timestamps.length; ++i) {
            vm.warp(uint256(type(uint48).max) - 1);
            irm = new FixedRateIrm(INITIAL_RATE, OWNER);
            _bindMarket();
            vm.warp(timestamps[i]);
            uint256 elapsed = timestamps[i] - (uint256(type(uint48).max) - 1);
            _updateAndAssert(0, 800 ether, _expectedInterest(800 ether, INITIAL_RATE, elapsed), INITIAL_RATE);
        }
    }

    function test_RevertWhen_TimestampPrecedesLastUpdate_PreservesState() public {
        _bindMarket();
        vm.warp(START - 1);
        _expectUpdateRevert(800 ether);
    }

    function test_RevertWhen_InterestMultiplicationOverflows_PreservesState() public {
        _bindMarket();
        vm.warp(START + 1);
        _expectUpdateRevert(type(uint256).max);
    }

    function test_RevertWhen_CompoundingOverflows_PreservesState() public {
        _bindMarket();
        vm.warp(START + (uint256(1) << 200));
        _expectUpdateRevert(800 ether);
    }

    function _expectUnauthorized(address caller) internal {
        vm.recordLogs();
        vm.prank(caller);
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irm.updateInterestRate(0, 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function _expectUpdateRevert(uint256 debt) internal {
        vm.recordLogs();
        vm.prank(address(market));
        vm.expectRevert(stdError.arithmeticError);
        irm.updateInterestRate(0, debt);
        assertEq(vm.getRecordedLogs().length, 0);
        _assertState(INITIAL_RATE, uint48(START));
    }

    function _updateAndAssert(uint256 supply, uint256 debt, uint256 expectedInterest, uint256 expectedRate) internal {
        vm.recordLogs();
        vm.prank(address(market));
        (uint256 interest, uint256 rate) = irm.updateInterestRate(supply, debt);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(interest, expectedInterest, "accrued interest");
        assertEq(rate, expectedRate, "borrow rate");
        _assertState(expectedRate, uint48(block.timestamp));
        assertEq(irm.owner(), OWNER);
        assertEq(irm.market(), address(market));
        assertEq(logs.length, 1);
        _assertStateLog(logs[0], expectedRate, uint48(block.timestamp));
    }
}
