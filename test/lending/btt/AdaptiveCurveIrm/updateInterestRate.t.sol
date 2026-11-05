// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {AdaptiveCurveIrmCommon} from "./AdaptiveCurveIrmCommon.t.sol";

contract AdaptiveCurveIrmUpdateInterestRateTest is AdaptiveCurveIrmCommon {
    function test_RevertWhen_CallerIsNotMarket_IncludingOwnerAndUnsetMarket() public {
        _expectUnauthorized(OWNER);
        _expectUnauthorized(OTHER);
        _assertState(0, 0);
        _bindMarket();
        _expectUnauthorized(OWNER);
        _expectUnauthorized(OTHER);
        _assertState(INITIAL_RATE, uint48(START));
    }

    function test_WhenElapsedTimeIsZero_AppliesCurveWithoutAdaptingOrAccruing() public {
        _bindMarket();
        _updateAndAssert(1000 ether, 400 ether, 0, 625_000_000, INITIAL_RATE);
        _updateAndAssert(1000 ether, 900 ether, 0, 2_500_000_000, INITIAL_RATE);
    }

    function testFuzz_WhenUtilizationEqualsTarget_PreservesRateAndAccrues(uint256 units, uint256 elapsed) public {
        units = bound(units, 1, 1e24);
        elapsed = bound(elapsed, 1, 365 days);
        _bindMarket();
        vm.warp(START + elapsed);
        _updateAndAssert(
            units * 5,
            units * 4,
            _expectedInterest(units * 4, uint256(INITIAL_RATE), elapsed),
            uint256(INITIAL_RATE),
            INITIAL_RATE
        );
    }

    function test_WhenUtilizationIsAboveTarget_IncreasesRateUsingTimeAveragedCurve() public {
        _bindMarket();
        vm.warp(START + 100_000);
        // err = 1/2, adaptation = 0.05. ExpLib's polynomial gives endpoint
        // 1.05125 and midpoint 1.0253125; the trapezoid average is 1.02546875.
        // The upper curve multiplier is 2.5, so the returned average is 2563671875.
        _updateAndAssert(
            1000 ether, 900 ether, _expectedInterest(900 ether, 2_563_671_875, 100_000), 2_563_671_875, 1_051_250_000
        );
    }

    function test_WhenUtilizationIsBelowTarget_DecreasesRateUsingTimeAveragedCurve() public {
        _bindMarket();
        vm.warp(START + 100_000);
        // err = -1/2, adaptation = -0.05. Endpoint 0.95125, midpoint 0.9753125,
        // average 0.97546875; the lower curve multiplies by 0.625 and rounds down.
        _updateAndAssert(
            1000 ether, 400 ether, _expectedInterest(400 ether, 609_667_968, 100_000), 609_667_968, 951_250_000
        );
    }

    function test_WhenBorrowedAmountIsZero_AccruesNothingButStillAdapts() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _updateAndAssert(1000 ether, 0, 0, 237_968_750, 905_000_000);
    }

    function test_WhenSupplyIsZero_TreatsUtilizationAsZeroEvenWithDebt() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _updateAndAssert(0, 800 ether, _expectedInterest(800 ether, 237_968_750, 100_000), 237_968_750, 905_000_000);
    }

    function test_WhenSupplyAndDebtAreZero_StillAdaptsAndEmits() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _updateAndAssert(0, 0, 0, 237_968_750, 905_000_000);
    }

    function test_WhenPositiveAdaptationReachesCap_BoundsEndpointAndMidpoint() public {
        _bindMarket();
        vm.warp(START + 365 days);
        uint256 averageRate = uint256((INITIAL_RATE + 3 * config.maxRateAtTarget) / 4) * 4;
        _updateAndAssert(
            1000 ether,
            1000 ether,
            _expectedInterest(1000 ether, averageRate, 365 days),
            averageRate,
            config.maxRateAtTarget
        );
    }

    function test_WhenNegativeAdaptationReachesFloor_BoundsEndpointAndMidpoint() public {
        _bindMarket();
        vm.warp(START + 365 days);
        uint256 averageRate = uint256((INITIAL_RATE + 3 * config.minRateAtTarget) / 4) / 4;
        _updateAndAssert(1000 ether, 0, 0, averageRate, config.minRateAtTarget);
    }

    function test_WhenOnlyEndpointExceedsMaximum_BoundsEndpointAndKeepsMidpoint() public {
        config.maxRateAtTarget = 1_040_000_000;
        irm = new AdaptiveCurveIrm(config, OWNER);
        _bindMarket();
        vm.warp(START + 100_000);

        // At 90% utilization, adaptation is 0.05: the endpoint is 1_051_250_000
        // and midpoint is 1_025_312_500. Only the endpoint is capped at 1_040_000_000.
        // (1_000_000_000 + 1_040_000_000 + 2 * 1_025_312_500) / 4 * 2.5 = 2_556_640_625.
        _updateAndAssert(
            1000 ether, 900 ether, _expectedInterest(900 ether, 2_556_640_625, 100_000), 2_556_640_625, 1_040_000_000
        );
    }

    function test_WhenOnlyEndpointFallsBelowMinimum_BoundsEndpointAndKeepsMidpoint() public {
        config.minRateAtTarget = 960_000_000;
        irm = new AdaptiveCurveIrm(config, OWNER);
        _bindMarket();
        vm.warp(START + 100_000);

        // At 40% utilization, adaptation is -0.05: the endpoint is 951_250_000
        // and midpoint is 975_312_500. Only the endpoint is floored at 960_000_000.
        // (1_000_000_000 + 960_000_000 + 2 * 975_312_500) / 4 * 0.625 rounds down to 611_035_156.
        _updateAndAssert(
            1000 ether, 400 ether, _expectedInterest(400 ether, 611_035_156, 100_000), 611_035_156, 960_000_000
        );
    }

    function test_WhenDebtExceedsSupply_DoesNotClampUtilization() public {
        _bindMarket();
        _updateAndAssert(1000 ether, 1100 ether, 0, 5_500_000_000, INITIAL_RATE);
    }

    function test_WhenTargetIsOne_AcceptsFullUtilizationButRejectsExcessDebt() public {
        config.targetUtilization = 1e18;
        irm = new AdaptiveCurveIrm(config, OWNER);
        _bindMarket();
        vm.warp(START + 100_000);
        _updateAndAssert(
            1000 ether,
            1000 ether,
            _expectedInterest(1000 ether, uint256(INITIAL_RATE), 100_000),
            uint256(INITIAL_RATE),
            INITIAL_RATE
        );
        _expectUpdateRevert(1000 ether, 1001 ether, stdError.divisionError);
    }

    function test_WhenCalledRepeatedly_UsesLastCheckpointAndEmitsEvenAtSameTime() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _updateAndAssert(
            1000 ether, 900 ether, _expectedInterest(900 ether, 2_563_671_875, 100_000), 2_563_671_875, 1_051_250_000
        );
        _updateAndAssert(1000 ether, 800 ether, 0, 1_051_250_000, 1_051_250_000);
        vm.warp(START + 200_000);
        _updateAndAssert(
            1000 ether, 800 ether, _expectedInterest(800 ether, 1_051_250_000, 100_000), 1_051_250_000, 1_051_250_000
        );
    }

    function test_WhenTimestampIsZeroMaximumOrCrossesUint48_StoresLow48Bits() public {
        vm.warp(0);
        _bindMarket();
        _updateAndAssert(1000 ether, 800 ether, 0, uint256(INITIAL_RATE), INITIAL_RATE);

        uint256[3] memory timestamps = [uint256(type(uint48).max), uint256(1) << 48, (uint256(1) << 48) + 37];
        for (uint256 i; i < timestamps.length; ++i) {
            vm.warp(uint256(type(uint48).max) - 1);
            irm = new AdaptiveCurveIrm(config, OWNER);
            _bindMarket();
            vm.warp(timestamps[i]);
            uint256 elapsed = timestamps[i] - (uint256(type(uint48).max) - 1);
            _updateAndAssert(
                1000 ether,
                800 ether,
                _expectedInterest(800 ether, uint256(INITIAL_RATE), elapsed),
                uint256(INITIAL_RATE),
                INITIAL_RATE
            );
        }
    }

    function test_RevertWhen_TimestampPrecedesLastUpdate_PreservesState() public {
        _bindMarket();
        vm.warp(START - 1);
        _expectUpdateRevert(1000 ether, 800 ether, stdError.arithmeticError);
    }

    function test_RevertWhen_UtilizationMultiplicationOverflows_PreservesState() public {
        _bindMarket();
        _expectUpdateRevert(1, type(uint256).max, stdError.arithmeticError);
    }

    function test_RevertWhen_InterestMultiplicationOverflows_PreservesState() public {
        _bindMarket();
        vm.warp(START + 1);
        // Zero supply bypasses utilization multiplication, isolating the interest overflow.
        _expectUpdateRevert(0, type(uint256).max, stdError.arithmeticError);
    }

    function test_RevertWhen_CompoundingOverflows_PreservesState() public {
        _bindMarket();
        vm.warp(START + (uint256(1) << 200));
        _expectUpdateRevert(1000 ether, 800 ether, stdError.arithmeticError);
    }

    function _expectUnauthorized(address caller) internal {
        vm.recordLogs();
        vm.prank(caller);
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irm.updateInterestRate(0, 0);
        assertEq(vm.getRecordedLogs().length, 0);
        _assertConfig(config);
    }

    function _expectUpdateRevert(uint256 supply, uint256 debt, bytes memory errorData) internal {
        AdaptiveCurveIrm.IRState memory beforeState = _readState();
        vm.recordLogs();
        vm.prank(address(market));
        vm.expectRevert(errorData);
        irm.updateInterestRate(supply, debt);
        assertEq(vm.getRecordedLogs().length, 0);
        _assertState(beforeState.rateAtTarget, beforeState.lastUpdate);
        _assertConfig(config);
    }

    function _updateAndAssert(
        uint256 supply,
        uint256 debt,
        uint256 expectedInterest,
        uint256 expectedRate,
        int256 endRate
    ) internal {
        vm.recordLogs();
        vm.prank(address(market));
        (uint256 interest, uint256 rate) = irm.updateInterestRate(supply, debt);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(interest, expectedInterest, "accrued interest");
        assertEq(rate, expectedRate, "average borrow rate");
        _assertState(endRate, uint48(block.timestamp));
        _assertConfig(config);
        assertEq(irm.owner(), OWNER);
        assertEq(irm.market(), address(market));
        assertEq(logs.length, 1);
        _assertStateLog(logs[0], endRate, uint48(block.timestamp));
    }
}
