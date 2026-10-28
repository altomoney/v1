// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {
    PegResponsiveExponentialIrmConfig,
    IRState,
    IPegResponsiveExponentialIrmErrors,
    IPegResponsiveExponentialIrmEvents
} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {stdError} from "forge-std/StdError.sol";
import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmSetIrmConfigTest is PegResponsiveExponentialIrmCommon {
    error MockPausedQueryReverted(uint256 code);

    uint256 private constant PAUSED_REVERT_CODE = 0xC0FFEE;

    function test_RevertWhen_CallerIsNotOwner_BeforeValidationOrCheckpoint() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        irm.setIrmConfig(invalidConfig);

        _assertIrmConfig(irmConfig);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_CallerIsPendingOwner() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;
        vm.prank(OWNER);
        irm.transferOwnership(PENDING_OWNER);
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(PENDING_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PENDING_OWNER));
        irm.setIrmConfig(invalidConfig);

        _assertIrmConfig(irmConfig);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_StressPriceIsZero() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidPriceConfig.selector
        );
    }

    function test_RevertWhen_RecoveryPriceExceedsMaximum() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.recoveryPrice = irm.MAX_RECOVERY_PRICE() + 1;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidPriceConfig.selector
        );
    }

    function test_RevertWhen_StressPriceEqualsRecoveryPrice() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = invalidConfig.recoveryPrice;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidPriceConfig.selector
        );
    }

    function test_RevertWhen_StressPriceExceedsRecoveryPrice() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = invalidConfig.recoveryPrice + 1;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidPriceConfig.selector
        );
    }

    function test_RevertWhen_StressRateIsZero() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = 0;
        invalidConfig.stressRate = 0;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector
        );
    }

    function test_RevertWhen_BaseRateExceedsStressRate() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = invalidConfig.stressRate + 1;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector
        );
    }

    function test_RevertWhen_StressRateEqualsMaxRate() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressRate = invalidConfig.maxRate;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector
        );
    }

    function test_RevertWhen_StressRateExceedsMaxRate() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressRate = invalidConfig.maxRate + 1;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector
        );
    }

    function test_RevertWhen_MaxRateExceedsMaximumBorrowRate() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.maxRate = irm.MAX_BORROW_RATE() + 1;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector
        );
    }

    function test_RevertWhen_DoublingDistanceIsZero() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.doublingDistance = 0;
        _expectConfigRevert(
            invalidConfig,
            IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidControllerConfig.selector
        );
    }

    function test_RevertWhen_RecoveryDelayIsZero() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.recoveryDelay = 0;
        _expectConfigRevert(
            invalidConfig,
            IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidControllerConfig.selector
        );
    }

    function test_RevertWhen_MaxOracleAgeIsZero() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(
            invalidConfig,
            IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidControllerConfig.selector
        );
    }

    function test_RevertWhen_PriceAndLaterGroupsAreInvalid_PrioritizesPriceError() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;
        invalidConfig.stressRate = invalidConfig.maxRate;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidPriceConfig.selector
        );
    }

    function test_RevertWhen_RateAndControllerGroupsAreInvalid_PrioritizesRateError() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressRate = invalidConfig.maxRate;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector
        );
    }

    function test_RevertWhen_ConfigIsInvalid_BeforeCheckpointingMarket() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.maxOracleAge = 0;
        _bindMarket();
        _mockPausedQueryRevert();

        _expectConfigRevert(
            invalidConfig,
            IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidControllerConfig.selector
        );
    }

    function test_AcceptsPriceBoundaryConfigurations() external {
        PegResponsiveExponentialIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.stressPrice = 1;
        boundaryConfig.recoveryPrice = 2;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.stressPrice = boundaryConfig.recoveryPrice - 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.recoveryPrice = irm.MAX_RECOVERY_PRICE();
        _setAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsRateBoundaryConfigurations() external {
        PegResponsiveExponentialIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.baseRate = 0;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.baseRate = 0;
        boundaryConfig.stressRate = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.baseRate = boundaryConfig.stressRate;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxRate = boundaryConfig.stressRate + 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxRate = irm.MAX_BORROW_RATE();
        _setAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsControllerBoundaryConfigurations() external {
        PegResponsiveExponentialIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.doublingDistance = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.recoveryDelay = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxOracleAge = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.doublingDistance = type(uint256).max;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.recoveryDelay = type(uint48).max;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxOracleAge = type(uint48).max;
        _setAndAssertConfig(boundaryConfig);
    }

    function test_DoesNotRequireRelationshipBetweenRecoveryDelayAndMaxOracleAge() external {
        PegResponsiveExponentialIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.recoveryDelay = 2;
        boundaryConfig.maxOracleAge = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig.maxOracleAge = 2;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig.maxOracleAge = 3;
        _setAndAssertConfig(boundaryConfig);
    }

    function test_WhenMarketIsUnset_SkipsCheckpointAndStoresEveryField() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        oracle.setGetPriceReverts(true);
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        _setIrmConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertIrmConfig(newConfig);
        _assertIRState(stateBefore);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[0].data, abi.encode(newConfig));
    }

    function test_WhenMarketIsPaused_QueriesExactPauseTypeAndSkipsAccrual() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        _pauseMarket();
        oracle.setGetPriceReverts(true);
        IRState memory stateBefore = _readIRState();
        vm.expectCall(address(market), _pausedCall(), 1);

        _setIrmConfigAsOwner(newConfig);

        _assertIrmConfig(newConfig);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_PausedQueryReverts_BubblesAndRollsBack() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert(_pausedQueryRevertData());
        irm.setIrmConfig(newConfig);

        _assertIrmConfig(irmConfig);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_PausedReturnDataIsMalformed_RollsBack() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        vm.mockCall(address(market), _pausedCall(), hex"01");
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert();
        irm.setIrmConfig(newConfig);

        _assertIrmConfig(irmConfig);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_AccrualRevertsAfterCallback_RollsBackNestedState() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        _prepareMarketAccrualOverflow();
        IRState memory stateBefore = _readIRState();
        vm.expectCall(address(market), _pausedCall(), 1);
        vm.expectCall(address(market), _accrueInterestCall(), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        irm.setIrmConfig(newConfig);

        _assertIrmConfig(irmConfig);
        _assertIRState(stateBefore);
    }

    function test_WhenCallbackRaisesRateAboveNewMax_AppliesNewCurve() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.stressRate = irmConfig.baseRate;
        newConfig.maxRate = irmConfig.stressRate - 1;
        _bindMarket();
        vm.warp(DEFAULT_NOW + 1);
        _setCurrentObservation(STRESS_PRICE);
        IRState memory stateBefore = _readIRState();
        assertLe(stateBefore.borrowRate, newConfig.maxRate);
        vm.expectCall(address(market), _accrueInterestCall(), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 2);

        _setIrmConfigAsOwner(newConfig);

        stateBefore.borrowRate = newConfig.stressRate;
        stateBefore.stressMode = true;
        stateBefore.lastUpdate = uint48(block.timestamp);
        _assertIrmConfig(newConfig);
        _assertIRState(stateBefore);
    }

    function test_When_CallbackLowersRateToNewMaxOrBelow_UsesPostCheckpointStateAndOldConfig() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.baseRate = 1;
        newConfig.stressRate = 1;
        newConfig.maxRate = (irmConfig.baseRate + irmConfig.stressRate) / 2;
        _bindMarket();
        vm.warp(DEFAULT_NOW + 100);
        IRState memory seededState = IRState({
            borrowRate: irmConfig.stressRate,
            lastUpdate: uint48(block.timestamp - 100),
            recoveryStartedAt: 0,
            stressMode: false
        });
        _setIRState(seededState);
        _setCurrentObservation(RECOVERY_PRICE);
        assertGt(seededState.borrowRate, newConfig.maxRate);
        vm.expectCall(address(market), _accrueInterestCall(), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 2);

        vm.recordLogs();
        _setIrmConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = IRState({
            borrowRate: irmConfig.baseRate, lastUpdate: uint48(block.timestamp), recoveryStartedAt: 0, stressMode: false
        });
        assertLt(expectedState.borrowRate, newConfig.maxRate);
        _assertIrmConfig(newConfig);
        IRState memory finalState = IRState({
            borrowRate: newConfig.baseRate,
            lastUpdate: expectedState.lastUpdate,
            recoveryStartedAt: 0,
            stressMode: false
        });
        _assertIRState(finalState);
        assertEq(market.irm(), address(irm));
        assertEq(logs.length, 5);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.BorrowRateUpdated.selector);
        assertEq(
            logs[0].data,
            abi.encode(seededState.borrowRate, expectedState.borrowRate, RECOVERY_PRICE, uint48(block.timestamp), true)
        );
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
        _assertIrmEvent(logs[2], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[2].data, abi.encode(newConfig));
        _assertIrmEvent(logs[3], IPegResponsiveExponentialIrmEvents.BorrowRateUpdated.selector);
        assertEq(
            logs[3].data,
            abi.encode(expectedState.borrowRate, newConfig.baseRate, RECOVERY_PRICE, uint48(block.timestamp), true)
        );
        _assertIrmEvent(logs[4], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[4].data, abi.encode(finalState));
    }

    function test_WhenOracleIsInvalid_ClampsHeldRateToNewMax() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.maxRate = irmConfig.stressRate + 1;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = newConfig.maxRate + 1;
        _setIRState(seededState);

        oracle.setGetPriceReverts(true);
        _setIrmConfigAsOwner(newConfig);

        seededState.borrowRate = newConfig.maxRate;
        _assertIrmConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_When_PostCheckpointRateEqualsNewMax_AcceptsBoundary() external {
        oracle.setGetPriceReverts(true);
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.maxRate = irmConfig.stressRate + 1;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = newConfig.maxRate;
        _setIRState(seededState);

        _setIrmConfigAsOwner(newConfig);

        _assertIrmConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_WhenConfigEqualsStored_StillCheckpointsAndEmitsReplacement() external {
        _bindMarket();
        vm.expectCall(address(market), _accrueInterestCall(), 1);

        vm.recordLogs();
        _setIrmConfigAsOwner(irmConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(market.irm(), address(irm));
        _assertIrmConfig(irmConfig);
        assertEq(logs.length, 5);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.BorrowRateUpdated.selector);
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        _assertIrmEvent(logs[2], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[2].data, abi.encode(irmConfig));
    }

    function test_RaisesStoredRateToNewBaseImmediately() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = 1;
        _setIRState(seededState);

        _setIrmConfigAsOwner(newConfig);

        assertLt(seededState.borrowRate, newConfig.baseRate);
        assertLt(seededState.borrowRate, newConfig.stressRate);
        seededState.borrowRate = newConfig.baseRate;
        _assertIrmConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_ReevaluatesStressAgainstNewThresholds() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.stressPrice = RECOVERY_PRICE - 1;
        IRState memory seededState = _readIRState();
        seededState.stressMode = false;
        _setIRState(seededState);
        _setCurrentObservation(STRESS_PRICE);

        _setIrmConfigAsOwner(newConfig);

        seededState.stressMode = true;
        seededState.borrowRate = irm.targetBorrowRate(STRESS_PRICE);
        _assertIrmConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_WhenRecoveryIsActive_RestartsConfirmationAndEmitsExactOrder() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);

        vm.recordLogs();
        _setIrmConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = seededState;
        expectedState.recoveryStartedAt = uint48(block.timestamp);
        _assertIrmConfig(newConfig);
        _assertIRState(expectedState);
        assertEq(logs.length, 5);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[0].data, abi.encode(newConfig));
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.StressStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(true, uint48(0), uint256(0)));
        _assertIrmEvent(logs[2], IPegResponsiveExponentialIrmEvents.StressStateUpdated.selector);
        assertEq(logs[2].data, abi.encode(true, uint48(block.timestamp), RECOVERY_PRICE));
        _assertIrmEvent(logs[3], IPegResponsiveExponentialIrmEvents.BorrowRateUpdated.selector);
        _assertIrmEvent(logs[4], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[4].data, abi.encode(expectedState));
    }

    function testFuzz_InvalidObservationKeepsRateWithinNewBounds(
        uint256 heldRate,
        uint256 baseRate,
        uint256 stressRate,
        uint256 maxRate,
        bool stressed,
        uint8 marketState,
        uint8 failure
    ) external {
        marketState = uint8(bound(marketState, 0, 2));
        if (marketState != 0) _bindMarket();
        if (marketState == 2) _pauseMarket();
        heldRate = bound(heldRate, stressed ? irmConfig.stressRate : irmConfig.baseRate, irmConfig.maxRate);
        _setIRState(heldRate, uint48(block.timestamp), stressed ? uint48(block.timestamp - 1) : 0, stressed);
        IRState memory expected = _readIRState();
        vm.warp(block.timestamp + 100);

        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.maxRate = bound(maxRate, 2, MAX_RATE);
        newConfig.stressRate = bound(stressRate, 1, newConfig.maxRate - 1);
        newConfig.baseRate = bound(baseRate, 0, newConfig.stressRate);
        failure = uint8(bound(failure, 0, 4));
        if (failure == 0) oracle.setGetPriceReverts(true);
        if (failure == 1) _setObservation(RECOVERY_PRICE, uint48(block.timestamp), false);
        if (failure == 2) _setObservation(RECOVERY_PRICE, uint48(block.timestamp - irmConfig.maxOracleAge - 1), true);
        if (failure == 3) _setObservation(RECOVERY_PRICE, uint48(block.timestamp + 1), true);
        if (failure == 4) _setObservation(0, uint48(block.timestamp), true);

        _setIrmConfigAsOwner(newConfig);

        uint256 floor = stressed ? newConfig.stressRate : newConfig.baseRate;
        expected.borrowRate = heldRate;
        if (heldRate < floor) expected.borrowRate = floor;
        if (heldRate > newConfig.maxRate) expected.borrowRate = newConfig.maxRate;
        expected.recoveryStartedAt = 0;
        if (marketState == 1) expected.lastUpdate = uint48(block.timestamp);
        _assertIRState(expected);
        _assertIrmConfig(newConfig);
        (,,, uint256 previewRate) = irm.previewBorrowRate();
        assertEq(previewRate, expected.borrowRate);
    }

    function _expectConfigRevert(PegResponsiveExponentialIrmConfig memory invalidConfig, bytes4 selector) private {
        PegResponsiveExponentialIrmConfig memory configBefore = _readIrmConfig();
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.prank(OWNER);
        vm.expectRevert(selector);
        irm.setIrmConfig(invalidConfig);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertIrmConfig(configBefore);
        _assertIRState(stateBefore);
    }

    function _setAndAssertConfig(PegResponsiveExponentialIrmConfig memory newConfig) private {
        IRState memory stateBefore = _readIRState();
        _setIrmConfigAsOwner(newConfig);
        _assertIrmConfig(newConfig);
        stateBefore.borrowRate = irm.targetBorrowRate(RECOVERY_PRICE);
        _assertIRState(stateBefore);
    }

    function _setIrmConfigAsOwner(PegResponsiveExponentialIrmConfig memory newConfig) private {
        vm.prank(OWNER);
        irm.setIrmConfig(newConfig);
    }

    function _pausedCall() private pure returns (bytes memory) {
        return abi.encodeWithSelector(IPausable.paused.selector, PAUSE_TYPE);
    }

    function _accrueInterestCall() private pure returns (bytes memory) {
        return abi.encodeWithSelector(IMarketBase.accrueInterest.selector);
    }

    function _mockPausedQueryRevert() private {
        vm.mockCallRevert(address(market), _pausedCall(), _pausedQueryRevertData());
    }

    function _pausedQueryRevertData() private pure returns (bytes memory) {
        return abi.encodeWithSelector(MockPausedQueryReverted.selector, PAUSED_REVERT_CODE);
    }

    function _assertIrmEvent(Vm.Log memory log, bytes32 selector) private view {
        assertEq(log.emitter, address(irm));
        assertEq(log.topics[0], selector);
    }
}
