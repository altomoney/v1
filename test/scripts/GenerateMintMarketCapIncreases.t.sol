// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {MintMarketCapIncreaseMath} from "../../script/GenerateMintMarketCapIncreases.s.sol";

contract MintMarketCapIncreaseMathHarness {
    function calculateTarget(
        uint256 deploymentCeiling,
        uint256 oldEffectiveExposure,
        uint256 currentDebtCeiling,
        bool exposureCanGrow,
        uint256 roundingUnit,
        uint256 executionBuffer
    ) external pure returns (uint256, uint256, bool) {
        return MintMarketCapIncreaseMath.calculateTarget(
            deploymentCeiling, oldEffectiveExposure, currentDebtCeiling, exposureCanGrow, roundingUnit, executionBuffer
        );
    }

    function calculateMinterCeiling(uint256 debtCeiling, uint256 maxLiquidationLtv) external pure returns (uint256) {
        return MintMarketCapIncreaseMath.calculateMinterCeiling(debtCeiling, maxLiquidationLtv);
    }
}

contract GenerateMintMarketCapIncreasesTest is Test {
    MintMarketCapIncreaseMathHarness internal harness;

    function setUp() public {
        harness = new MintMarketCapIncreaseMathHarness();
    }

    function test_calculatesRoundedIncreaseWithExecutionBuffer() public view {
        (uint256 target, uint256 maximumAvailable, bool overCap) =
            harness.calculateTarget(60_000 ether, 3_915 ether, 50_000 ether, true, 1_000 ether, 1_000 ether);

        assertEq(maximumAvailable, 56_085 ether);
        assertEq(target, 55_000 ether);
        assertFalse(overCap);
    }

    function test_reportsExistingAggregateCapExcessWithoutIncreasing() public view {
        (uint256 target,, bool overCap) =
            harness.calculateTarget(60_000 ether, 49_650 ether, 11_000 ether, true, 1_000 ether, 1_000 ether);

        assertEq(target, 9_000 ether);
        assertTrue(overCap);
        assertLt(target, 11_000 ether);
    }

    function test_usesDeploymentMaximumAfterCompleteUnwind() public view {
        (uint256 target, uint256 maximumAvailable, bool overCap) =
            harness.calculateTarget(31_394 ether, 0, 31_000 ether, false, 1_000 ether, 1_000 ether);

        assertEq(maximumAvailable, 31_394 ether);
        assertEq(target, 31_394 ether);
        assertFalse(overCap);
    }

    function test_doesNotReserveExecutionBufferForNonGrowingBadDebt() public view {
        (uint256 target, uint256 maximumAvailable, bool overCap) =
            harness.calculateTarget(54_000 ether, 650 ether, 50_000 ether, false, 1_000 ether, 1_000 ether);

        assertEq(maximumAvailable, 53_350 ether);
        assertEq(target, 53_000 ether);
        assertFalse(overCap);
    }

    function test_doesNotProposeCeilingAboveRemainingCapacity() public view {
        (uint256 target, uint256 maximumAvailable, bool overCap) =
            harness.calculateTarget(20_000 ether, 20_500 ether, 2_000 ether, true, 1_000 ether, 1_000 ether);

        assertEq(maximumAvailable, 0);
        assertEq(target, 0);
        assertTrue(overCap);
    }

    function test_derivesSubmittedMinterCeilings() public view {
        assertEq(harness.calculateMinterCeiling(50_000 ether, 0.81 ether), 64_814.814814814814814814 ether);
        assertEq(harness.calculateMinterCeiling(11_000 ether, 0.78 ether), 14_807.692307692307692307 ether);
        assertEq(harness.calculateMinterCeiling(18_000 ether, 0.78 ether), 24_230.76923076923076923 ether);
        assertEq(harness.calculateMinterCeiling(2_000 ether, 0.72 ether), 2_916.666666666666666666 ether);
        assertEq(harness.calculateMinterCeiling(2_000 ether, 0.71 ether), 2_957.746478873239436619 ether);
        assertEq(harness.calculateMinterCeiling(30_000 ether, 0.81 ether), 38_888.888888888888888888 ether);
    }
}
