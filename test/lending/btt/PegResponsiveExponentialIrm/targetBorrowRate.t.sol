// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PegResponsiveExponentialIrmConfig, IRState} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";

import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmTargetBorrowRateTest is PegResponsiveExponentialIrmCommon {
    uint256 private constant WAD = 1e18;
    uint256 private constant LN_2 = 693_147_180_559_945_309;
    uint256 private constant MAX_RECOVERY = 1.01e18;

    function test_WhenPriceEqualsRecoveryPrice_ItReturnsBaseRate() external view {
        assertEq(irm.targetBorrowRate(RECOVERY_PRICE), BASE_RATE);
    }

    function test_WhenPriceIsAboveRecoveryPrice_ItReturnsBaseRate() external view {
        assertEq(irm.targetBorrowRate(RECOVERY_PRICE + 1), BASE_RATE);
    }

    function test_WhenPriceIsUint256Max_ItReturnsBaseRateWithoutSubtractiveMath() external view {
        assertEq(irm.targetBorrowRate(type(uint256).max), BASE_RATE);
    }

    function test_WhenPriceEqualsStressPrice_ItReturnsStressRate() external view {
        assertEq(irm.targetBorrowRate(STRESS_PRICE), STRESS_RATE);
    }

    function test_WhenPriceIsOneUnitBelowRecoveryPrice_ItUsesTwoStageFloorRounding() external view {
        uint256 price = RECOVERY_PRICE - 1;

        assertEq(irm.targetBorrowRate(price), _bridgeExpected(irmConfig, price));
    }

    function test_WhenPriceIsOneUnitAboveStressPrice_ItUsesTwoStageFloorRounding() external view {
        uint256 price = STRESS_PRICE + 1;

        assertEq(irm.targetBorrowRate(price), _bridgeExpected(irmConfig, price));
    }

    function test_WhenPriceIsTheExactBridgeMidpoint_ItReturnsTheMidpointRate() external view {
        assertEq(irm.targetBorrowRate(MID_BRIDGE_PRICE), (BASE_RATE + STRESS_RATE) / 2);
    }

    function test_WhenTwoStageRoundingDiffersFromSingleFraction_ItUsesTheImplementedTwoStageResult() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(4, 1, 1, 4, 5, 1);
        _useConfig(config);

        uint256 twoStageResult = irm.targetBorrowRate(3);
        uint256 singleFractionResult = config.baseRate + (config.stressRate - config.baseRate)
            * (config.recoveryPrice - 3) / (config.recoveryPrice - config.stressPrice);

        assertEq(twoStageResult, 1);
        assertEq(singleFractionResult, 2);
    }

    function test_WhenBridgeWidthIsOne_ItDoesNotDivideByZero() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(2, 1, 10, 20, 21, 1);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(1), 20);
    }

    function test_WhenBaseRateEqualsStressRate_TheBridgeIsFlat() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(10, 1, 100, 100, 101, 1);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(5), 100);
    }

    function test_WhenBaseRateIsZero_TheHealthyRateIsZeroAndTheBridgeRisesFromZero() external {
        PegResponsiveExponentialIrmConfig memory config = irmConfig;
        config.baseRate = 0;
        _useConfig(config);

        assertEq(irm.targetBorrowRate(type(uint256).max), 0);
        assertEq(irm.targetBorrowRate(RECOVERY_PRICE), 0);
        assertEq(irm.targetBorrowRate(RECOVERY_PRICE - 1), _bridgeExpected(config, RECOVERY_PRICE - 1));
        assertEq(irm.targetBorrowRate(MID_BRIDGE_PRICE), STRESS_RATE / 2);
        assertEq(irm.targetBorrowRate(STRESS_PRICE), STRESS_RATE);
        assertEq(irm.targetBorrowRate(STRESS_PRICE - DOUBLING_DISTANCE), STRESS_RATE * 2);
    }

    function test_WhenPriceIsOneUnitBelowStress_ItReturnsTheExactRoundedExponentialResult() external view {
        assertEq(irm.targetBorrowRate(STRESS_PRICE - 1), STRESS_RATE);
    }

    function test_WhenRawExponentFloorsToZero_ItReturnsStressRate() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(11, 10, 1, 2, 3, LN_2 + 1);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(9), 2);
    }

    function test_WhenExponentIsNonZeroButRateMultiplicationRoundsDown_ItReturnsStressRate() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(11, 10, 1, 2, 3, LN_2);
        _useConfig(config);

        assertEq(Math.mulDiv(LN_2, 1, config.doublingDistance), 1);
        assertEq(irm.targetBorrowRate(9), 2);
    }

    function test_WhenPriceIsOneDoublingDistanceBelowStress_ItReturnsTwiceStressRate() external view {
        assertEq(irm.targetBorrowRate(STRESS_PRICE - DOUBLING_DISTANCE), STRESS_RATE * 2);
    }

    function test_WhenPriceIsTwoDoublingDistancesBelowStress_ItReturnsFourTimesStressRate() external view {
        assertEq(irm.targetBorrowRate(STRESS_PRICE - 2 * DOUBLING_DISTANCE), STRESS_RATE * 4);
    }

    function test_WhenPriceIsHalfADoublingDistanceBelowStress_ItUsesTheExactExpLibApproximation() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1e18, 995e15, 100, 200, 10_000, DOUBLING_DISTANCE);
        _useConfig(config);

        uint256 expectedExponent = 346_573_590_279_972_654;
        uint256 expectedMultiplier = 1_406_630_217_019_747_831;

        assertEq(Math.mulDiv(LN_2, DOUBLING_DISTANCE / 2, DOUBLING_DISTANCE), expectedExponent);
        assertEq(Math.mulDiv(config.stressRate, expectedMultiplier, WAD), 281);
        assertEq(irm.targetBorrowRate(config.stressPrice - DOUBLING_DISTANCE / 2), 281);
    }

    function test_WhenUncappedRateIsBelowMaxRate_ItReturnsUncappedRate() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1e18, 995e15, 50, 100, 201, DOUBLING_DISTANCE);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(config.stressPrice - config.doublingDistance), 200);
    }

    function test_WhenUncappedRateEqualsMaxRate_ItReturnsMaxRate() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1e18, 995e15, 50, 100, 200, DOUBLING_DISTANCE);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(config.stressPrice - config.doublingDistance), config.maxRate);
    }

    function test_WhenUncappedRateExceedsMaxRate_ItReturnsMaxRate() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1e18, 995e15, 50, 100, 199, DOUBLING_DISTANCE);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(config.stressPrice - config.doublingDistance), config.maxRate);
    }

    function test_WhenRawExponentIsBelowClamp_ItPassesTheRawExponentThrough() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1.01e18, 1e18, 50, 100, 200, 1e15);
        _useConfig(config);
        uint256 stressDrop = 72e15;

        assertLt(Math.mulDiv(LN_2, stressDrop, config.doublingDistance), irm.MAX_EXPONENT_INPUT());
        assertEq(irm.targetBorrowRate(config.stressPrice - stressDrop), config.maxRate);
    }

    function test_WhenRawExponentEqualsClamp_ItUsesTheExactBoundary() external {
        uint256 stressDrop = 298_429_495_007_687_623;
        uint256 doublingDistance = 4_137_111_261_210_139;
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1.01e18, 1e18, 50, 100, 200, doublingDistance);
        _useConfig(config);

        assertEq(Math.mulDiv(LN_2, stressDrop, doublingDistance), irm.MAX_EXPONENT_INPUT());
        assertEq(irm.targetBorrowRate(config.stressPrice - stressDrop), config.maxRate);
    }

    function test_WhenRawExponentExceedsClamp_ItClampsWithoutReverting() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1.01e18, 1e18, 50, 100, 200, 1e15);
        _useConfig(config);
        uint256 stressDrop = 73e15;

        assertGt(Math.mulDiv(LN_2, stressDrop, config.doublingDistance), irm.MAX_EXPONENT_INPUT());
        assertEq(irm.targetBorrowRate(config.stressPrice - stressDrop), config.maxRate);
    }

    function test_WhenPriceIsZeroAndDepegIsExtreme_ItCapsWithoutOverflow() external {
        PegResponsiveExponentialIrmConfig memory config = _irmConfig(1.01e18, 1e18, 1, 1, irm.MAX_BORROW_RATE(), 1);
        _useConfig(config);

        assertEq(irm.targetBorrowRate(0), config.maxRate);
    }

    function testFuzz_ValidConfigurationProducesBoundedMonotonicCurve(
        uint256 rawRecoveryPrice,
        uint256 rawStressPrice,
        uint256 rawBaseRate,
        uint256 rawStressRate,
        uint256 rawMaxRate,
        uint256 rawDoublingDistance,
        uint48 rawRecoveryDelay,
        uint48 rawMaxOracleAge,
        uint256 firstPrice,
        uint256 secondPrice
    ) external {
        PegResponsiveExponentialIrmConfig memory config = _boundValidConfig(
            rawRecoveryPrice,
            rawStressPrice,
            rawBaseRate,
            rawStressRate,
            rawMaxRate,
            rawDoublingDistance,
            rawRecoveryDelay,
            rawMaxOracleAge
        );
        _useConfig(config);

        uint256 lowerPrice = firstPrice < secondPrice ? firstPrice : secondPrice;
        uint256 higherPrice = firstPrice < secondPrice ? secondPrice : firstPrice;
        uint256 lowerPriceRate = irm.targetBorrowRate(lowerPrice);
        uint256 higherPriceRate = irm.targetBorrowRate(higherPrice);

        assertGe(lowerPriceRate, config.baseRate);
        assertLe(lowerPriceRate, config.maxRate);
        assertGe(lowerPriceRate, higherPriceRate);
        assertGe(higherPriceRate, config.baseRate);
        assertLe(higherPriceRate, config.maxRate);
        if (lowerPrice < config.stressPrice) assertGe(lowerPriceRate, config.stressRate);
        if (higherPrice < config.stressPrice) assertGe(higherPriceRate, config.stressRate);
        assertEq(irm.targetBorrowRate(config.recoveryPrice), config.baseRate);
        assertEq(irm.targetBorrowRate(config.stressPrice), config.stressRate);
    }

    function test_WhenCallSucceeds_ItDoesNotReadOracleRequireMarketOrMutateState() external {
        _mockOracleReturnData(hex"01");
        _setIRState(STRESS_RATE, uint48(block.timestamp), uint48(block.timestamp), true);
        IRState memory stateBefore = _readIRState();
        PegResponsiveExponentialIrmConfig memory configBefore = _readIrmConfig();

        vm.recordLogs();
        vm.prank(NON_OWNER);
        uint256 rate = irm.targetBorrowRate(RECOVERY_PRICE);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(rate, BASE_RATE);
        assertLt(rate, STRESS_RATE);
        assertEq(address(irm.market()), address(0));
        assertEq(logs.length, 0);
        _assertIRState(stateBefore);
        _assertIrmConfig(configBefore);
    }

    function _useConfig(PegResponsiveExponentialIrmConfig memory config) private {
        irmConfig = config;
        irm = _deployIrm(config);
    }

    function _irmConfig(
        uint256 recoveryPrice,
        uint256 stressPrice,
        uint256 baseRate,
        uint256 stressRate,
        uint256 maxRate,
        uint256 doublingDistance
    ) private pure returns (PegResponsiveExponentialIrmConfig memory config) {
        config = PegResponsiveExponentialIrmConfig({
            recoveryPrice: recoveryPrice,
            stressPrice: stressPrice,
            baseRate: baseRate,
            stressRate: stressRate,
            maxRate: maxRate,
            doublingDistance: doublingDistance,
            recoveryDelay: 1,
            maxOracleAge: 1
        });
    }

    function _bridgeExpected(PegResponsiveExponentialIrmConfig memory config, uint256 price)
        private
        pure
        returns (uint256)
    {
        uint256 position = Math.mulDiv(config.recoveryPrice - price, WAD, config.recoveryPrice - config.stressPrice);
        return config.baseRate + Math.mulDiv(config.stressRate - config.baseRate, position, WAD);
    }

    function _boundValidConfig(
        uint256 rawRecoveryPrice,
        uint256 rawStressPrice,
        uint256 rawBaseRate,
        uint256 rawStressRate,
        uint256 rawMaxRate,
        uint256 rawDoublingDistance,
        uint48 rawRecoveryDelay,
        uint48 rawMaxOracleAge
    ) private pure returns (PegResponsiveExponentialIrmConfig memory config) {
        config.stressPrice = bound(rawStressPrice, 1, MAX_RECOVERY - 1);
        config.recoveryPrice = bound(rawRecoveryPrice, config.stressPrice + 1, MAX_RECOVERY);
        config.baseRate = bound(rawBaseRate, 0, MAX_RATE - 2);
        config.stressRate = bound(rawStressRate, Math.max(config.baseRate, 1), MAX_RATE - 1);
        config.maxRate = bound(rawMaxRate, config.stressRate + 1, MAX_RATE);
        config.doublingDistance = rawDoublingDistance == 0 ? 1 : rawDoublingDistance;
        config.recoveryDelay = rawRecoveryDelay == 0 ? 1 : rawRecoveryDelay;
        config.maxOracleAge = rawMaxOracleAge == 0 ? 1 : rawMaxOracleAge;
    }
}
