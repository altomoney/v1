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

    function test_RevertWhen_BaseRateIsZero() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = 0;
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
        invalidConfig.baseRate = 0;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(
            invalidConfig, IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidPriceConfig.selector
        );
    }

    function test_RevertWhen_RateAndControllerGroupsAreInvalid_PrioritizesRateError() external {
        PegResponsiveExponentialIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = 0;
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
        boundaryConfig.baseRate = 1;
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
        _mockOracleReturnData(hex"01");
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        _setIrmConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertIrmConfig(newConfig);
        _assertIRState(stateBefore);
        assertEq(logs.length, 1);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[0].data, abi.encode(newConfig));
    }

    function test_WhenMarketIsPaused_QueriesExactPauseTypeAndSkipsAccrual() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        _pauseMarket();
        _mockOracleReturnData(hex"01");
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

    function test_RevertWhen_CallbackRaisesRateAboveNewMax_UsesPostCheckpointOldConfigState() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.stressRate = irmConfig.baseRate;
        newConfig.maxRate = irmConfig.stressRate - 1;
        _bindMarket();
        vm.warp(DEFAULT_NOW + 1);
        _setCurrentObservation(STRESS_PRICE);
        IRState memory stateBefore = _readIRState();
        assertLe(stateBefore.borrowRate, newConfig.maxRate);
        vm.expectCall(address(market), _accrueInterestCall(), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        vm.expectRevert(IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector);
        irm.setIrmConfig(newConfig);

        _assertIrmConfig(irmConfig);
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
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.recordLogs();
        _setIrmConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = IRState({
            borrowRate: irmConfig.baseRate,
            lastUpdate: uint48(block.timestamp),
            recoveryStartedAt: 0,
            stressMode: false
        });
        assertLt(expectedState.borrowRate, newConfig.maxRate);
        _assertIrmConfig(newConfig);
        _assertIRState(expectedState);
        assertEq(market.irm(), address(irm));
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.BorrowRateUpdated.selector);
        assertEq(
            logs[0].data,
            abi.encode(seededState.borrowRate, expectedState.borrowRate, RECOVERY_PRICE, uint48(block.timestamp), true)
        );
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
        _assertIrmEvent(logs[2], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[2].data, abi.encode(newConfig));
    }

    function test_RevertWhen_PostCheckpointRateExceedsNewMax() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.maxRate = irmConfig.stressRate + 1;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = newConfig.maxRate + 1;
        _setIRState(seededState);

        vm.prank(OWNER);
        vm.expectRevert(IPegResponsiveExponentialIrmErrors.PegResponsiveExponentialIrmInvalidRateConfig.selector);
        irm.setIrmConfig(newConfig);

        _assertIrmConfig(irmConfig);
        _assertIRState(seededState);
    }

    function test_When_PostCheckpointRateEqualsNewMax_AcceptsBoundary() external {
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
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.BorrowRateUpdated.selector);
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        _assertIrmEvent(logs[2], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[2].data, abi.encode(irmConfig));
    }

    function test_AcceptsStoredRateBelowNewBaseAndStressWithoutImmediateRepricing() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = 1;
        _setIRState(seededState);

        _setIrmConfigAsOwner(newConfig);

        assertLt(seededState.borrowRate, newConfig.baseRate);
        assertLt(seededState.borrowRate, newConfig.stressRate);
        _assertIrmConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_DoesNotReadOracleOrReevaluateStressAgainstNewThresholds() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.stressPrice = RECOVERY_PRICE - 1;
        IRState memory seededState = _readIRState();
        seededState.stressMode = false;
        _setIRState(seededState);
        _mockOracleReturnData(hex"01");

        _setIrmConfigAsOwner(newConfig);

        _assertIrmConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_WhenRecoveryIsActive_ClearsOnlyRecoveryAndEmitsExactOrder() external {
        PegResponsiveExponentialIrmConfig memory newConfig = irmConfig;
        newConfig.recoveryDelay += 1;
        IRState memory seededState =
            IRState({borrowRate: irmConfig.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);

        vm.recordLogs();
        _setIrmConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = seededState;
        expectedState.recoveryStartedAt = 0;
        _assertIrmConfig(newConfig);
        _assertIRState(expectedState);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveExponentialIrmEvents.StressStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(true, uint48(0), uint256(0)));
        _assertIrmEvent(logs[1], IPegResponsiveExponentialIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
        _assertIrmEvent(logs[2], IPegResponsiveExponentialIrmEvents.SetIrmConfig.selector);
        assertEq(logs[2].data, abi.encode(newConfig));
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
