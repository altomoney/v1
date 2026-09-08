// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PegResponsiveExponentialIrmConfig, IRState} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";

import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmPreviewBorrowRateTest is PegResponsiveExponentialIrmCommon {
    function test_RevertWhen_OracleIsANonContractAddress() external {
        irm = _deployIrm(irmConfig, address(0xBEEF), OWNER);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert();
        irm.previewBorrowRate();

        _assertIRState(stateBefore);
    }

    function test_RevertWhen_OracleReturnsShortData() external {
        _assertMalformedOracleData(hex"01");
    }

    function test_RevertWhen_OracleReturnsInvalidBoolEncoding() external {
        _assertMalformedOracleData(_rawOracleData(RECOVERY_PRICE, block.timestamp, 2));
    }

    function test_RevertWhen_OracleReturnsDirtyUint48Encoding() external {
        _assertMalformedOracleData(_rawOracleData(RECOVERY_PRICE, uint256(type(uint48).max) + 1, 1));
    }

    function test_WhenOracleCallReverts_ItReturnsTheStoredRateAndCanonicalInvalidTuple() external {
        _setIRState(STRESS_RATE, uint48(block.timestamp - 1), 77, true);
        oracle.setGetPriceReverts(true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(0, 0, false, STRESS_RATE);

        _assertIRState(stateBefore);
    }

    function test_WhenOracleValidFlagIsFalse_ItRejectsBeforeUsingOtherMetadata() external {
        uint48 futureObservedAt = uint48(block.timestamp + 1);
        _setObservation(type(uint256).max, futureObservedAt, false);

        _assertPreview(0, futureObservedAt, false, BASE_RATE);
    }

    function test_WhenOraclePriceIsZero_ItRejectsBeforeUsingTimestampMetadata() external {
        uint48 futureObservedAt = uint48(block.timestamp + 1);
        _setObservation(0, futureObservedAt, true);

        _assertPreview(0, futureObservedAt, false, BASE_RATE);
    }

    function test_WhenObservedAtIsZero_ItRejectsTheObservation() external {
        _setObservation(RECOVERY_PRICE, 0, true);

        _assertPreview(0, 0, false, BASE_RATE);
    }

    function test_WhenObservedAtIsInTheFuture_ItRejectsWithoutSubtracting() external {
        uint48 futureObservedAt = uint48(block.timestamp + 1);
        _setObservation(RECOVERY_PRICE, futureObservedAt, true);

        _assertPreview(0, futureObservedAt, false, BASE_RATE);
    }

    function test_WhenObservationAgeExceedsMaximum_ItRejectsTheObservation() external {
        uint48 staleObservedAt = uint48(block.timestamp - MAX_ORACLE_AGE - 1);
        _setObservation(RECOVERY_PRICE, staleObservedAt, true);

        _assertPreview(0, staleObservedAt, false, BASE_RATE);
    }

    function test_WhenObservationAgeEqualsMaximum_ItAcceptsTheObservation() external {
        uint48 observedAt = uint48(block.timestamp - MAX_ORACLE_AGE);
        _setObservation(RECOVERY_PRICE, observedAt, true);

        _assertPreview(RECOVERY_PRICE, observedAt, true, BASE_RATE);
    }

    function test_WhenObservedAtEqualsCurrentTimestamp_ItAcceptsTheObservation() external {
        _setCurrentObservation(MID_BRIDGE_PRICE);

        _assertPreview(MID_BRIDGE_PRICE, uint48(block.timestamp), true, irm.targetBorrowRate(MID_BRIDGE_PRICE));
    }

    function test_WhenPriceIsUint256Max_ItAcceptsTheUnboundedHealthyPrice() external {
        _setCurrentObservation(type(uint256).max);

        _assertPreview(type(uint256).max, uint48(block.timestamp), true, BASE_RATE);
    }

    function test_WhenObservationIsInvalidOutsideStress_ItDoesNotMutateRecovery() external {
        _setObservation(RECOVERY_PRICE, uint48(block.timestamp), false);

        _assertInvalidPreviewDoesNotMutate(false);
    }

    function test_WhenObservationIsInvalidDuringStress_ItDoesNotMutateRecovery() external {
        _setObservation(RECOVERY_PRICE, uint48(block.timestamp), false);

        _assertInvalidPreviewDoesNotMutate(true);
    }

    function test_WhenObservationIsInvalidAboveUint48Timestamp_ItBypassesProspectiveRecoveryCast() external {
        vm.warp(uint256(type(uint48).max) + 1);
        _setObservation(RECOVERY_PRICE, type(uint48).max, false);
        _setIRState(STRESS_RATE, type(uint48).max, 0, true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(0, type(uint48).max, false, STRESS_RATE);

        _assertIRState(stateBefore);
    }

    function test_WhenNotStressedAndPriceIsBelowStress_ItPreviewsExponentialRateWithoutMutating() external {
        uint256 price = STRESS_PRICE - DOUBLING_DISTANCE;
        _setCurrentObservation(price);
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        IRState memory stateBefore = _readIRState();

        _assertPreview(price, uint48(block.timestamp), true, STRESS_RATE * 2);

        _assertIRState(stateBefore);
    }

    function test_WhenNotStressedAndPriceEqualsStress_ItPreviewsStressRateWithoutMutating() external {
        _setCurrentObservation(STRESS_PRICE);
        IRState memory stateBefore = _readIRState();

        _assertPreview(STRESS_PRICE, uint48(block.timestamp), true, STRESS_RATE);

        _assertIRState(stateBefore);
    }

    function test_WhenNotStressedAndPriceIsInBridge_ItPreviewsRawBridgeRate() external {
        _setCurrentObservation(MID_BRIDGE_PRICE);
        IRState memory stateBefore = _readIRState();

        _assertPreview(MID_BRIDGE_PRICE, uint48(block.timestamp), true, irm.targetBorrowRate(MID_BRIDGE_PRICE));

        _assertIRState(stateBefore);
    }

    function test_WhenNotStressedAndPriceIsHealthy_ItPreviewsBaseRate() external {
        _setCurrentObservation(RECOVERY_PRICE + 1);

        _assertPreview(RECOVERY_PRICE + 1, uint48(block.timestamp), true, BASE_RATE);
    }

    function test_WhenStressedBelowStressPrice_ItPreviewsRawExponentialAndDoesNotClearTimer() external {
        uint256 price = STRESS_PRICE - DOUBLING_DISTANCE;
        uint48 recoveryStartedAt = uint48(block.timestamp - 1);
        _setCurrentObservation(price);
        _setIRState(STRESS_RATE, uint48(block.timestamp), recoveryStartedAt, true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(price, uint48(block.timestamp), true, STRESS_RATE * 2);

        _assertIRState(stateBefore);
    }

    function test_WhenStressedAtStressPrice_ItPreviewsTheRawStressRate() external {
        _setCurrentObservation(STRESS_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertPreview(STRESS_PRICE, uint48(block.timestamp), true, STRESS_RATE);
    }

    function test_WhenStressedInBridge_ItFloorsThePreviewAtStressRateWithoutClearingTimer() external {
        uint48 recoveryStartedAt = uint48(block.timestamp - 1);
        _setCurrentObservation(MID_BRIDGE_PRICE);
        _setIRState(STRESS_RATE * 2, uint48(block.timestamp), recoveryStartedAt, true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(MID_BRIDGE_PRICE, uint48(block.timestamp), true, STRESS_RATE);

        _assertIRState(stateBefore);
    }

    function test_WhenStressedHealthyAndTimerIsZero_ItProspectivelyStartsRecoveryAndFloorsRate() external {
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(RECOVERY_PRICE, uint48(block.timestamp), true, STRESS_RATE);

        _assertIRState(stateBefore);
    }

    function test_RevertWhen_StressedHealthyTimerStartTimestampDoesNotFitUint48() external {
        vm.warp(uint256(type(uint48).max) + 1);
        _setObservation(RECOVERY_PRICE, type(uint48).max, true);
        _setIRState(STRESS_RATE, type(uint48).max, 0, true);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(48), block.timestamp)
        );
        irm.previewBorrowRate();

        _assertIRState(stateBefore);
    }

    function test_RevertWhen_ActiveRecoveryTimerIsInTheFuture() external {
        uint48 futureRecoveryStartedAt = uint48(block.timestamp + 1);
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), futureRecoveryStartedAt, true);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert(stdError.arithmeticError);
        irm.previewBorrowRate();

        _assertIRState(stateBefore);
    }

    function test_WhenRecoveryElapsedIsDelayMinusOne_ItPreviewsStressFloorWithoutMutation() external {
        _assertTimedRecoveryPreview(RECOVERY_DELAY - 1, STRESS_RATE);
    }

    function test_WhenRecoveryElapsedEqualsDelay_ItPreviewsBaseRateWithoutMutation() external {
        _assertTimedRecoveryPreview(RECOVERY_DELAY, BASE_RATE);
    }

    function test_WhenRecoveryElapsedExceedsDelay_ItPreviewsBaseRateWithoutMutation() external {
        _assertTimedRecoveryPreview(RECOVERY_DELAY + 1, BASE_RATE);
    }

    function test_WhenExistingTimerAndTimestampExceedUint48_ItDoesNotDowncastBeforeDelay() external {
        irmConfig.maxOracleAge = irmConfig.recoveryDelay;
        irm = _deployIrm(irmConfig);
        uint48 recoveryStartedAt = type(uint48).max;
        vm.warp(uint256(recoveryStartedAt) + 1);
        _setObservation(RECOVERY_PRICE, recoveryStartedAt, true);
        _setIRState(STRESS_RATE, recoveryStartedAt, recoveryStartedAt, true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(RECOVERY_PRICE, recoveryStartedAt, true, STRESS_RATE);

        _assertIRState(stateBefore);
    }

    function test_WhenExistingTimerAndTimestampExceedUint48_ItDoesNotDowncastAtDelayCompletion() external {
        irmConfig.maxOracleAge = irmConfig.recoveryDelay;
        irm = _deployIrm(irmConfig);
        uint48 recoveryStartedAt = type(uint48).max;
        vm.warp(uint256(recoveryStartedAt) + RECOVERY_DELAY);
        _setObservation(RECOVERY_PRICE, recoveryStartedAt, true);
        _setIRState(STRESS_RATE, recoveryStartedAt, recoveryStartedAt, true);
        IRState memory stateBefore = _readIRState();

        _assertPreview(RECOVERY_PRICE, recoveryStartedAt, true, BASE_RATE);

        _assertIRState(stateBefore);
    }

    function test_WhenBaseRateEqualsStressRate_ItReturnsTheEqualRawTarget() external {
        irmConfig.baseRate = irmConfig.stressRate;
        irm = _deployIrm(irmConfig);
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertPreview(RECOVERY_PRICE, uint48(block.timestamp), true, STRESS_RATE);
    }

    function test_WhenValidCallSucceeds_ItCallsOracleOnceWithoutMarketBindingAndChangesNothing() external {
        _setCurrentObservation(MID_BRIDGE_PRICE);
        IRState memory stateBefore = _readIRState();
        PegResponsiveExponentialIrmConfig memory configBefore = _readIrmConfig();

        vm.recordLogs();
        vm.prank(NON_OWNER);
        _assertPreview(MID_BRIDGE_PRICE, uint48(block.timestamp), true, irm.targetBorrowRate(MID_BRIDGE_PRICE));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(address(irm.market()), address(0));
        assertEq(logs.length, 0);
        _assertIRState(stateBefore);
        _assertIrmConfig(configBefore);
    }

    function _assertMalformedOracleData(bytes memory returnData) private {
        rawOracle.setRawReturnData(returnData);
        irm = _deployIrm(irmConfig, address(rawOracle), OWNER);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert();
        irm.previewBorrowRate();

        _assertIRState(stateBefore);
    }

    function _assertInvalidPreviewDoesNotMutate(bool stressMode) private {
        _setIRState(STRESS_RATE + 123, uint48(block.timestamp - 1), uint48(block.timestamp - 2), stressMode);
        IRState memory stateBefore = _readIRState();

        _assertPreview(0, uint48(block.timestamp), false, stateBefore.borrowRate);

        _assertIRState(stateBefore);
    }

    function _assertTimedRecoveryPreview(uint256 elapsed, uint256 expectedRate) private {
        uint48 recoveryStartedAt = uint48(block.timestamp);
        _setIRState(STRESS_RATE, recoveryStartedAt, recoveryStartedAt, true);
        vm.warp(block.timestamp + elapsed);
        _setCurrentObservation(RECOVERY_PRICE);
        IRState memory stateBefore = _readIRState();

        _assertPreview(RECOVERY_PRICE, uint48(block.timestamp), true, expectedRate);

        _assertIRState(stateBefore);
    }

    function _assertPreview(uint256 priceWad, uint48 observedAt, bool valid, uint256 borrowRate) private {
        vm.expectCall(address(oracle), _getPriceCall(), 1);
        (uint256 actualPriceWad, uint48 actualObservedAt, bool actualValid, uint256 actualBorrowRate) =
            irm.previewBorrowRate();

        assertEq(actualPriceWad, priceWad, "priceWad");
        assertEq(actualObservedAt, observedAt, "observedAt");
        assertEq(actualValid, valid, "oracleValid");
        assertEq(actualBorrowRate, borrowRate, "borrowRate");
    }
}
