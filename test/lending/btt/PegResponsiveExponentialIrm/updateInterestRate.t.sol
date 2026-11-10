// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    PegResponsiveExponentialIrmConfig,
    IRState,
    IPegResponsiveExponentialIrmEvents
} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmUpdateInterestRateTest is PegResponsiveExponentialIrmCommon {
    struct ProcessedObservation {
        uint256 priceWad;
        uint48 observedAt;
        bool valid;
    }

    struct MarketSnapshot {
        uint128 debtAssets;
        uint128 debtShares;
        uint128 supplyAssets;
        uint128 supplyShares;
        uint128 claimableFees;
    }

    function setUp() public override {
        super.setUp();
        _bindMarket();
    }

    function test_RevertWhen_CallerIsOwnerButNotMarket() external {
        _assertUnauthorized(OWNER);
    }

    function test_RevertWhen_CallerIsPendingOwnerButNotMarket() external {
        vm.prank(OWNER);
        irm.transferOwnership(PENDING_OWNER);

        _assertUnauthorized(PENDING_OWNER);
    }

    function test_RevertWhen_CallerIsArbitraryNonMarketAddress() external {
        _setIRState(BASE_RATE, uint48(block.timestamp + 1), 0, false);
        _assertUnauthorized(NON_OWNER);
    }

    function test_RevertWhen_BlockTimestampIsBeforeLastUpdate_WithoutReadingOracle() external {
        _mockOracleReturnData(hex"01");
        _setIRState(BASE_RATE, uint48(block.timestamp + 1), 0, false);

        _assertCheckpointRevert(stdError.arithmeticError);
    }

    function test_RevertWhen_CompoundInterestCalculationOverflows_WithoutReadingOracle() external {
        _mockOracleReturnData(hex"01");
        _setIRState(1, 0, 0, false);
        vm.warp(uint256(1) << 128);

        _assertCheckpointRevert(stdError.arithmeticError);
    }

    function test_WhenElapsedTimeIsZero_ItStillProcessesOracleCheckpoint() external {
        _setCurrentObservation(STRESS_PRICE);
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        (uint256 interest,) =
            _assertCheckpoint(expectedState, _observation(STRESS_PRICE, uint48(block.timestamp), true), true);

        assertEq(interest, 0);
    }

    function test_WhenTotalBorrowedIsZero_ItStillProcessesOracleCheckpoint() external {
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 365 days);
        _setCurrentObservation(MID_BRIDGE_PRICE);
        uint256 bridgeRate = irm.targetBorrowRate(MID_BRIDGE_PRICE);
        IRState memory expectedState = _state(bridgeRate, uint48(block.timestamp), 0, false);

        (uint256 interest,) =
            _assertCheckpoint(expectedState, _observation(MID_BRIDGE_PRICE, uint48(block.timestamp), true), false);

        assertEq(interest, 0);
    }

    function test_WhenAccrualInputsAreSupported_ItReturnsIndependentExactOldRateVector() external {
        uint256 storedRate = 1_000_000_000;
        uint256 elapsed = 1_000;
        uint256 debt = 1_000e18;
        _openDebt(debt);
        _setIRState(storedRate, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + elapsed);
        _setCurrentObservation(RECOVERY_PRICE);
        IRState memory expectedState = _state(BASE_RATE, uint48(block.timestamp), 0, false);

        (uint256 interest, uint256 returnedRate) =
            _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), false);

        assertEq(interest, 1_000_000_500_000_000);
        assertEq(returnedRate, storedRate);
        assertEq(expectedState.borrowRate, BASE_RATE);
    }

    function test_RevertWhen_OracleIsANonContractAddress() external {
        _replaceBoundIrm(irmConfig, address(0xBEEF));
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.expectRevert();
        market.accrueInterest();

        _assertIRState(stateBefore);
        assertEq(vm.getRecordedLogs().length, 0);
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

    function test_WhenOracleCallReverts_ItHoldsRateAndInterruptsActiveRecovery() external {
        uint48 recoveryStartedAt = uint48(block.timestamp - 1);
        _setIRState(STRESS_RATE * 2, uint48(block.timestamp - 10), recoveryStartedAt, true);
        oracle.setGetPriceReverts(true);
        IRState memory expectedState = _state(STRESS_RATE * 2, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(0, 0, false), true);
    }

    function test_WhenOracleValidFlagIsFalse_ItPreservesObservedAtAndHoldsRate() external {
        _assertInvalidObservation(type(uint256).max, uint48(block.timestamp + 1), false);
    }

    function test_WhenOraclePriceIsZero_ItPreservesObservedAtAndHoldsRate() external {
        _assertInvalidObservation(0, uint48(block.timestamp + 1), true);
    }

    function test_WhenOracleObservedAtIsZero_ItHoldsRate() external {
        _assertInvalidObservation(RECOVERY_PRICE, 0, true);
    }

    function test_WhenOracleObservedAtIsInFuture_ItRejectsWithoutSubtracting() external {
        _assertInvalidObservation(RECOVERY_PRICE, uint48(block.timestamp + 1), true);
    }

    function test_WhenOracleObservationIsStale_ItHoldsRate() external {
        _assertInvalidObservation(RECOVERY_PRICE, uint48(block.timestamp - MAX_ORACLE_AGE - 1), true);
    }

    function test_WhenInvalidObservationFindsFutureRecoveryTimer_ItClearsWithoutSubtracting() external {
        uint48 observedAt = uint48(block.timestamp);
        uint48 recoveryStartedAt = uint48(block.timestamp + 1);
        _setObservation(RECOVERY_PRICE, observedAt, false);
        _setIRState(STRESS_RATE, uint48(block.timestamp - 10), recoveryStartedAt, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(0, observedAt, false), true);
    }

    function test_WhenInvalidObservationHasZeroTimerDuringStress_ItPreservesStressWithoutStressEvent() external {
        uint48 observedAt = uint48(block.timestamp);
        _setObservation(RECOVERY_PRICE, observedAt, false);
        _setIRState(STRESS_RATE * 2, uint48(block.timestamp - 10), 0, true);
        IRState memory expectedState = _state(STRESS_RATE * 2, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(0, observedAt, false), false);
    }

    function test_WhenObservationAgeEqualsMaximum_ItAcceptsTheObservation() external {
        uint48 observedAt = uint48(block.timestamp - MAX_ORACLE_AGE);
        _setObservation(MID_BRIDGE_PRICE, observedAt, true);
        uint256 bridgeRate = irm.targetBorrowRate(MID_BRIDGE_PRICE);
        IRState memory expectedState = _state(bridgeRate, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(MID_BRIDGE_PRICE, observedAt, true), false);
    }

    function test_WhenFreshPriceIsUint256Max_ItAcceptsPriceAndInstallsBaseRate() external {
        _setCurrentObservation(type(uint256).max);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, false);
        IRState memory expectedState = _state(BASE_RATE, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(type(uint256).max, uint48(block.timestamp), true), false);
    }

    function test_WhenNotStressedAndPriceIsBelowStress_ItEntersStressAndInstallsExponentialRate() external {
        uint256 price = STRESS_PRICE - DOUBLING_DISTANCE;
        _setCurrentObservation(price);
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        IRState memory expectedState = _state(STRESS_RATE * 2, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(price, uint48(block.timestamp), true), true);
    }

    function test_WhenNotStressedAndDeepPriceHitsCap_ItInstallsMaxRate() external {
        uint256 price = STRESS_PRICE - 10 * DOUBLING_DISTANCE;
        assertEq(irm.targetBorrowRate(price), MAX_RATE);
        _setCurrentObservation(price);
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        IRState memory expectedState = _state(MAX_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(price, uint48(block.timestamp), true), true);
    }

    function test_WhenNotStressedAndPriceEqualsStress_ItEntersAtInclusiveBoundary() external {
        _setCurrentObservation(STRESS_PRICE);
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(STRESS_PRICE, uint48(block.timestamp), true), true);
    }

    function test_WhenNotStressedAndPriceIsOneAboveStress_ItRemainsHealthyAndInstallsBridgeRate() external {
        uint256 price = STRESS_PRICE + 1;
        _setCurrentObservation(price);
        uint256 bridgeRate = irm.targetBorrowRate(price);
        IRState memory expectedState = _state(bridgeRate, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(price, uint48(block.timestamp), true), false);
    }

    function test_WhenNotStressedAndPriceIsStrictBridge_ItInstallsTargetWithoutMovementLimit() external {
        _setCurrentObservation(MID_BRIDGE_PRICE);
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        uint256 bridgeRate = irm.targetBorrowRate(MID_BRIDGE_PRICE);
        IRState memory expectedState = _state(bridgeRate, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(MID_BRIDGE_PRICE, uint48(block.timestamp), true), false);
    }

    function test_WhenNotStressedAndPriceEqualsRecovery_ItInstallsBaseRate() external {
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, false);
        IRState memory expectedState = _state(BASE_RATE, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), false);
    }

    function test_WhenStressedBelowStress_ItKeepsStressAndInstallsRawExponentialRate() external {
        uint256 price = STRESS_PRICE - DOUBLING_DISTANCE;
        _setCurrentObservation(price);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, true);
        IRState memory expectedState = _state(STRESS_RATE * 2, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(price, uint48(block.timestamp), true), false);
    }

    function test_WhenStressedAtStressPrice_ItKeepsRawStressRateWithoutStressEvent() external {
        _setCurrentObservation(STRESS_PRICE);
        _setIRState(STRESS_RATE * 2, uint48(block.timestamp), 0, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(STRESS_PRICE, uint48(block.timestamp), true), false);
    }

    function test_WhenStressedInBridge_ItFloorsRawBridgeTargetAtStressRate() external {
        _setCurrentObservation(MID_BRIDGE_PRICE);
        _setIRState(STRESS_RATE * 2, uint48(block.timestamp), 0, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(MID_BRIDGE_PRICE, uint48(block.timestamp), true), false);
    }

    function test_WhenStressedBelowRecoveryWithFutureTimer_ItClearsWithoutSubtracting() external {
        uint48 futureRecoveryStartedAt = uint48(block.timestamp + 1);
        _setCurrentObservation(MID_BRIDGE_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), futureRecoveryStartedAt, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(MID_BRIDGE_PRICE, uint48(block.timestamp), true), true);
    }

    function test_WhenStressedHealthyAndTimerIsZero_ItStartsRecoveryAndKeepsStressFloor() external {
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE * 2, uint48(block.timestamp), 0, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), uint48(block.timestamp), true);

        _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), true);
    }

    function test_RevertWhen_RecoveryStartTimestampDoesNotFitUint48() external {
        vm.warp(uint256(type(uint48).max) + 1);
        _setObservation(RECOVERY_PRICE, type(uint48).max, true);
        _setIRState(STRESS_RATE, type(uint48).max, 0, true);
        bytes memory revertData =
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(48), block.timestamp);

        _assertCheckpointRevert(revertData);
    }

    function test_RevertWhen_ActiveRecoveryTimerIsInFutureAtHealthyPrice() external {
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), uint48(block.timestamp + 1), true);

        _assertCheckpointRevert(stdError.arithmeticError);
    }

    function test_WhenRecoveryElapsedIsDelayMinusOne_ItPreservesStressAndTimer() external {
        _assertTimedRecoveryCheckpoint(RECOVERY_DELAY - 1, true);
    }

    function test_WhenRecoveryElapsedEqualsDelay_ItExitsStressAtInclusiveBoundary() external {
        _assertTimedRecoveryCheckpoint(RECOVERY_DELAY, false);
    }

    function test_WhenRecoveryElapsedExceedsDelay_ItExitsStress() external {
        _assertTimedRecoveryCheckpoint(RECOVERY_DELAY + 1, false);
    }

    function test_WhenBaseRateEqualsStressRate_HealthyStressFloorEqualityIsPreserved() external {
        irmConfig.baseRate = irmConfig.stressRate;
        _replaceBoundIrm(irmConfig, address(oracle));
        _setCurrentObservation(RECOVERY_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), uint48(block.timestamp), true);

        _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), true);
    }

    function test_WhenBaseRateEqualsStressRate_StrictBridgePreservesEqualRawTarget() external {
        irmConfig.baseRate = irmConfig.stressRate;
        _replaceBoundIrm(irmConfig, address(oracle));
        _setCurrentObservation(MID_BRIDGE_PRICE);
        _setIRState(STRESS_RATE, uint48(block.timestamp), 0, true);
        IRState memory expectedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);

        _assertCheckpoint(expectedState, _observation(MID_BRIDGE_PRICE, uint48(block.timestamp), true), false);
    }

    function test_RevertWhen_FinalLastUpdateTimestampDoesNotFitUint48_AndRollsBackStressWrite() external {
        vm.warp(uint256(type(uint48).max) + 1);
        _setObservation(RECOVERY_PRICE, type(uint48).max, false);
        _setIRState(STRESS_RATE, type(uint48).max, type(uint48).max, true);
        bytes memory revertData =
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(48), block.timestamp);

        IRState memory stateBefore = _readIRState();
        vm.expectRevert(revertData);
        market.accrueInterest();

        _assertIRState(stateBefore);
    }

    function test_WhenTimestampEqualsUint48Max_ItStoresBoundaryExactly() external {
        vm.warp(type(uint48).max);
        _setObservation(RECOVERY_PRICE, type(uint48).max, true);
        _setIRState(BASE_RATE, type(uint48).max - 1, 0, false);
        IRState memory expectedState = _state(BASE_RATE, type(uint48).max, 0, false);

        _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, type(uint48).max, true), false);
    }

    function test_WhenInvalidObservationInterruptsRecovery_LaterHealthyObservationStartsNewTimer() external {
        uint48 originalStart = uint48(block.timestamp - 10);
        _setIRState(STRESS_RATE, uint48(block.timestamp), originalStart, true);
        _setObservation(RECOVERY_PRICE, uint48(block.timestamp), false);
        IRState memory interruptedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);
        _assertCheckpoint(interruptedState, _observation(0, uint48(block.timestamp), false), true);

        vm.warp(block.timestamp + 1);
        _setCurrentObservation(RECOVERY_PRICE);
        IRState memory restartedState = _state(STRESS_RATE, uint48(block.timestamp), uint48(block.timestamp), true);
        _assertCheckpoint(restartedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), true);
    }

    function test_WhenBelowRecoveryObservationInterruptsRecovery_LaterHealthyObservationStartsNewTimer() external {
        uint48 originalStart = uint48(block.timestamp - 10);
        _setIRState(STRESS_RATE, uint48(block.timestamp), originalStart, true);
        _setCurrentObservation(MID_BRIDGE_PRICE);
        IRState memory interruptedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);
        _assertCheckpoint(interruptedState, _observation(MID_BRIDGE_PRICE, uint48(block.timestamp), true), true);

        vm.warp(block.timestamp + 1);
        _setCurrentObservation(RECOVERY_PRICE);
        IRState memory restartedState = _state(STRESS_RATE, uint48(block.timestamp), uint48(block.timestamp), true);
        _assertCheckpoint(restartedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), true);
    }

    function test_WhenSameObservationRemainsFresh_ItCanStartAndCompleteRecovery() external {
        irmConfig.recoveryDelay = 100;
        irmConfig.maxOracleAge = 100;
        _replaceBoundIrm(irmConfig, address(oracle));
        uint48 observedAt = uint48(block.timestamp);
        _setObservation(RECOVERY_PRICE, observedAt, true);
        _setIRState(STRESS_RATE, observedAt, 0, true);
        IRState memory startedState = _state(STRESS_RATE, observedAt, observedAt, true);
        _assertCheckpoint(startedState, _observation(RECOVERY_PRICE, observedAt, true), true);

        vm.warp(block.timestamp + irmConfig.recoveryDelay);
        IRState memory recoveredState = _state(BASE_RATE, uint48(block.timestamp), 0, false);
        _assertCheckpoint(recoveredState, _observation(RECOVERY_PRICE, observedAt, true), true);
    }

    function test_WhenRecoveryObservationBecomesStale_ItInterruptsInsteadOfCompleting() external {
        irmConfig.recoveryDelay = 100;
        irmConfig.maxOracleAge = 10;
        _replaceBoundIrm(irmConfig, address(oracle));
        uint48 observedAt = uint48(block.timestamp);
        _setObservation(RECOVERY_PRICE, observedAt, true);
        _setIRState(STRESS_RATE, observedAt, 0, true);
        IRState memory startedState = _state(STRESS_RATE, observedAt, observedAt, true);
        _assertCheckpoint(startedState, _observation(RECOVERY_PRICE, observedAt, true), true);

        vm.warp(block.timestamp + irmConfig.maxOracleAge + 1);
        IRState memory interruptedState = _state(STRESS_RATE, uint48(block.timestamp), 0, true);
        _assertCheckpoint(interruptedState, _observation(0, observedAt, false), true);
    }

    function test_CompleteEquilibriumLifecycle_AccruesOldRatesAndAppliesEachNewRateProspectively() external {
        uint256 debt = 1_000_000e18;
        _openDebt(debt);
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(MID_BRIDGE_PRICE, irm.targetBorrowRate(MID_BRIDGE_PRICE), 0, false, false, BASE_RATE);

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(STRESS_PRICE, STRESS_RATE, 0, true, true, irm.targetBorrowRate(MID_BRIDGE_PRICE));

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(STRESS_PRICE - 2 * DOUBLING_DISTANCE, STRESS_RATE * 4, 0, true, false, STRESS_RATE);

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(MID_BRIDGE_PRICE, STRESS_RATE, 0, true, false, STRESS_RATE * 4);

        vm.warp(block.timestamp + 10);
        uint48 recoveryStartedAt = uint48(block.timestamp);
        _assertLifecycleStep(RECOVERY_PRICE, STRESS_RATE, recoveryStartedAt, true, true, STRESS_RATE);

        vm.warp(block.timestamp + RECOVERY_DELAY - 1);
        _assertLifecycleStep(RECOVERY_PRICE, STRESS_RATE, recoveryStartedAt, true, false, STRESS_RATE);

        vm.warp(block.timestamp + 1);
        _assertLifecycleStep(RECOVERY_PRICE, BASE_RATE, 0, false, true, STRESS_RATE);
    }

    function test_WhenBaseRateIsZero_HealthyIntervalsAccrueNothingAndStressStillCharges() external {
        irmConfig.baseRate = 0;
        _replaceBoundIrm(irmConfig, address(oracle));
        uint256 debt = 1_000_000e18;
        _openDebt(debt);
        _setIRState(0, uint48(block.timestamp), 0, false);

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(RECOVERY_PRICE, 0, 0, false, false, 0);

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(MID_BRIDGE_PRICE, STRESS_RATE / 2, 0, false, false, 0);
        (uint128 debtAfterHealthyIntervals,) = market.totalBorrowed();
        assertEq(debtAfterHealthyIntervals, debt, "zero base rate accrued interest");

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(STRESS_PRICE, STRESS_RATE, 0, true, true, STRESS_RATE / 2);

        vm.warp(block.timestamp + 10);
        uint48 recoveryStartedAt = uint48(block.timestamp);
        _assertLifecycleStep(RECOVERY_PRICE, STRESS_RATE, recoveryStartedAt, true, true, STRESS_RATE);

        vm.warp(block.timestamp + RECOVERY_DELAY);
        _assertLifecycleStep(RECOVERY_PRICE, 0, 0, false, true, STRESS_RATE);
        (uint128 debtAfterStress,) = market.totalBorrowed();
        assertGt(debtAfterStress, debtAfterHealthyIntervals, "stress interval accrued interest");

        vm.warp(block.timestamp + 10);
        _assertLifecycleStep(RECOVERY_PRICE, 0, 0, false, false, 0);
        (uint128 debtAfterRecovery,) = market.totalBorrowed();
        assertEq(debtAfterRecovery, debtAfterStress, "recovered zero base rate accrued interest");
    }

    function test_WhenCheckpointSucceeds_ItCallsOracleOnceAndNeverQueriesMarketPauseState() external {
        _setCurrentObservation(RECOVERY_PRICE);
        bytes memory pausedCall = abi.encodeWithSignature("paused(bytes32)", PAUSE_TYPE);
        vm.mockCallRevert(address(market), pausedCall, hex"DEAD");
        vm.expectCall(address(oracle), _getPriceCall(), 1);
        IRState memory expectedState = _state(BASE_RATE, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), false);
    }

    function _assertUnauthorized(address caller) private {
        _mockOracleReturnData(hex"01");
        IRState memory stateBefore = _readIRState();
        vm.recordLogs();

        vm.prank(caller);
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irm.updateInterestRate(0, 0);

        _assertIRState(stateBefore);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function _assertCheckpointRevert(bytes memory revertData) private {
        IRState memory stateBefore = _readIRState();
        MarketSnapshot memory marketBefore = _marketSnapshot();
        vm.recordLogs();

        vm.expectRevert(revertData);
        market.accrueInterest();

        _assertIRState(stateBefore);
        _assertMarketAccounting(marketBefore, 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function _assertMalformedOracleData(bytes memory returnData) private {
        rawOracle.setRawReturnData(returnData);
        _replaceBoundIrm(irmConfig, address(rawOracle));
        IRState memory stateBefore = _readIRState();
        vm.expectCall(address(rawOracle), _getPriceCall(), 1);
        vm.recordLogs();

        vm.expectRevert();
        market.accrueInterest();

        _assertIRState(stateBefore);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function _assertInvalidObservation(uint256 priceWad, uint48 observedAt, bool valid) private {
        uint256 heldRate = STRESS_RATE + 123;
        _setObservation(priceWad, observedAt, valid);
        _setIRState(heldRate, uint48(block.timestamp - 10), 0, false);
        IRState memory expectedState = _state(heldRate, uint48(block.timestamp), 0, false);

        _assertCheckpoint(expectedState, _observation(0, observedAt, false), false);
    }

    function _assertTimedRecoveryCheckpoint(uint256 elapsed, bool remainsStressed) private {
        uint48 recoveryStartedAt = uint48(block.timestamp);
        _setIRState(STRESS_RATE, recoveryStartedAt, recoveryStartedAt, true);
        vm.warp(block.timestamp + elapsed);
        _setCurrentObservation(RECOVERY_PRICE);
        IRState memory expectedState = _state(
            remainsStressed ? STRESS_RATE : BASE_RATE,
            uint48(block.timestamp),
            remainsStressed ? recoveryStartedAt : 0,
            remainsStressed
        );

        _assertCheckpoint(expectedState, _observation(RECOVERY_PRICE, uint48(block.timestamp), true), !remainsStressed);
    }

    function _assertLifecycleStep(
        uint256 priceWad,
        uint256 nextRate,
        uint48 nextRecoveryStartedAt,
        bool nextStressMode,
        bool stressEventExpected,
        uint256 expectedReturnedRate
    ) private {
        _setCurrentObservation(priceWad);
        IRState memory expectedState = _state(nextRate, uint48(block.timestamp), nextRecoveryStartedAt, nextStressMode);
        (, uint256 returnedRate) =
            _assertCheckpoint(expectedState, _observation(priceWad, uint48(block.timestamp), true), stressEventExpected);

        assertEq(returnedRate, expectedReturnedRate, "prospective rate ordering");
    }

    function _assertCheckpoint(
        IRState memory expectedState,
        ProcessedObservation memory observation,
        bool stressEventExpected
    ) private returns (uint256 interest, uint256 borrowRate) {
        IRState memory stateBefore = _readIRState();
        MarketSnapshot memory marketBefore = _marketSnapshot();
        uint256 expectedInterest = _expectedInterest(
            marketBefore.debtAssets, stateBefore.borrowRate, block.timestamp - stateBefore.lastUpdate
        );

        if (stressEventExpected) {
            vm.expectEmit(false, false, false, true, address(irm));
            emit IPegResponsiveExponentialIrmEvents.StressStateUpdated(
                expectedState.stressMode, expectedState.recoveryStartedAt, observation.priceWad
            );
        }
        vm.expectEmit(false, false, false, true, address(irm));
        emit IPegResponsiveExponentialIrmEvents.BorrowRateUpdated(
            stateBefore.borrowRate,
            expectedState.borrowRate,
            observation.priceWad,
            observation.observedAt,
            observation.valid
        );
        vm.expectEmit(false, false, false, true, address(irm));
        emit IPegResponsiveExponentialIrmEvents.IRStateUpdated(expectedState);

        if (expectedInterest != 0) {
            vm.expectEmit(false, false, false, true, address(market));
            emit IMarketEvents.AccrueInterest(
                stateBefore.borrowRate,
                expectedInterest,
                uint128(uint256(marketBefore.debtAssets) + expectedInterest),
                marketBefore.supplyAssets
            );
        }

        vm.recordLogs();
        market.accrueInterest();
        interest = expectedInterest;
        borrowRate = stateBefore.borrowRate;
        _assertMarketAccounting(marketBefore, expectedInterest);
        assertEq(
            vm.getRecordedLogs().length, (stressEventExpected ? 3 : 2) + (expectedInterest == 0 ? 0 : 1), "event count"
        );
        _assertIRState(expectedState);
    }

    function _marketSnapshot() private view returns (MarketSnapshot memory snapshot) {
        (snapshot.debtAssets, snapshot.debtShares) = market.totalBorrowed();
        (snapshot.supplyAssets, snapshot.supplyShares) = market.totalSupply();
        snapshot.claimableFees = market.claimableFeesAssets();
    }

    function _assertMarketAccounting(MarketSnapshot memory beforeAccrual, uint256 interest) private view {
        MarketSnapshot memory afterAccrual = _marketSnapshot();
        assertEq(afterAccrual.debtAssets, uint256(beforeAccrual.debtAssets) + interest, "debt assets");
        assertEq(afterAccrual.debtShares, beforeAccrual.debtShares, "debt shares");
        assertEq(afterAccrual.supplyAssets, beforeAccrual.supplyAssets, "supply assets");
        assertEq(afterAccrual.supplyShares, beforeAccrual.supplyShares, "supply shares");
        assertEq(afterAccrual.claimableFees, uint256(beforeAccrual.claimableFees) + interest, "claimable fees");
    }

    function _replaceBoundIrm(PegResponsiveExponentialIrmConfig memory config, address oracleAddress) private {
        irmConfig = config;
        irm = _deployIrm(config, oracleAddress, OWNER);
        _bindMarket();
    }

    function _state(uint256 borrowRate, uint48 lastUpdate, uint48 recoveryStartedAt, bool stressMode)
        private
        pure
        returns (IRState memory state)
    {
        return IRState({
            borrowRate: borrowRate, lastUpdate: lastUpdate, recoveryStartedAt: recoveryStartedAt, stressMode: stressMode
        });
    }

    function _observation(uint256 priceWad, uint48 observedAt, bool valid)
        private
        pure
        returns (ProcessedObservation memory observation)
    {
        return ProcessedObservation({priceWad: priceWad, observedAt: observedAt, valid: valid});
    }
}
