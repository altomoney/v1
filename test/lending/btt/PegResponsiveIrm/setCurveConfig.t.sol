// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {
    CurveConfig,
    IRState,
    IPegResponsiveIrmErrors,
    IPegResponsiveIrmEvents
} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {MockPegResponsiveIrmMarket} from "@alto-test/lending/btt/mocks/MockPegResponsiveIrmMarket.sol";
import {PegResponsiveIrmCommon} from "./PegResponsiveIrmCommon.t.sol";

contract PegResponsiveIrmSetCurveConfigTest is PegResponsiveIrmCommon {
    error MockPausedQueryReverted(uint256 code);

    uint256 private constant PAUSED_REVERT_CODE = 0xC0FFEE;

    function test_RevertWhen_CallerIsNotOwner_BeforeValidationOrCheckpoint() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressPrice = 0;
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        irm.setCurveConfig(invalidConfig);

        _assertCurveConfig(cfg);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_CallerIsPendingOwner() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressPrice = 0;
        vm.prank(OWNER);
        irm.transferOwnership(PENDING_OWNER);
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(PENDING_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PENDING_OWNER));
        irm.setCurveConfig(invalidConfig);

        _assertCurveConfig(cfg);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_StressPriceIsZero() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressPrice = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_RecoveryPriceExceedsMaximum() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.recoveryPrice = irm.MAX_RECOVERY_PRICE() + 1;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_StressPriceEqualsRecoveryPrice() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressPrice = invalidConfig.recoveryPrice;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_StressPriceExceedsRecoveryPrice() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressPrice = invalidConfig.recoveryPrice + 1;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_BaseRateIsZero() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.baseRate = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_BaseRateExceedsStressRate() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.baseRate = invalidConfig.stressRate + 1;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_StressRateEqualsMaxRate() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressRate = invalidConfig.maxRate;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_StressRateExceedsMaxRate() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressRate = invalidConfig.maxRate + 1;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_MaxRateExceedsMaximumBorrowRate() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.maxRate = irm.MAX_BORROW_RATE() + 1;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_DoublingDistanceIsZero() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.doublingDistance = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector);
    }

    function test_RevertWhen_RecoveryDelayIsZero() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.recoveryDelay = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector);
    }

    function test_RevertWhen_MaxOracleAgeIsZero() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector);
    }

    function test_RevertWhen_PriceAndLaterGroupsAreInvalid_PrioritizesPriceError() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.stressPrice = 0;
        invalidConfig.baseRate = 0;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_RateAndControllerGroupsAreInvalid_PrioritizesRateError() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.baseRate = 0;
        invalidConfig.maxOracleAge = 0;
        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_ConfigIsInvalid_BeforeCheckpointingMarket() external {
        CurveConfig memory invalidConfig = cfg;
        invalidConfig.maxOracleAge = 0;
        _bindMarket();
        _mockPausedQueryRevert();

        _expectConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector);
    }

    function test_AcceptsPriceBoundaryConfigurations() external {
        CurveConfig memory boundaryConfig = cfg;
        boundaryConfig.stressPrice = 1;
        boundaryConfig.recoveryPrice = 2;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.stressPrice = boundaryConfig.recoveryPrice - 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.recoveryPrice = irm.MAX_RECOVERY_PRICE();
        _setAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsRateBoundaryConfigurations() external {
        CurveConfig memory boundaryConfig = cfg;
        boundaryConfig.baseRate = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.baseRate = boundaryConfig.stressRate;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.maxRate = boundaryConfig.stressRate + 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.maxRate = irm.MAX_BORROW_RATE();
        _setAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsControllerBoundaryConfigurations() external {
        CurveConfig memory boundaryConfig = cfg;
        boundaryConfig.doublingDistance = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.recoveryDelay = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.maxOracleAge = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.doublingDistance = type(uint256).max;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.recoveryDelay = type(uint48).max;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig = cfg;
        boundaryConfig.maxOracleAge = type(uint48).max;
        _setAndAssertConfig(boundaryConfig);
    }

    function test_DoesNotRequireRelationshipBetweenRecoveryDelayAndMaxOracleAge() external {
        CurveConfig memory boundaryConfig = cfg;
        boundaryConfig.recoveryDelay = 2;
        boundaryConfig.maxOracleAge = 1;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig.maxOracleAge = 2;
        _setAndAssertConfig(boundaryConfig);

        boundaryConfig.maxOracleAge = 3;
        _setAndAssertConfig(boundaryConfig);
    }

    function test_WhenMarketIsUnset_SkipsCheckpointAndStoresEveryField() external {
        CurveConfig memory newConfig = cfg;
        newConfig.recoveryDelay += 1;
        _mockOracleReturnData(hex"01");
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        _setCurveConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertCurveConfig(newConfig);
        _assertIRState(stateBefore);
        assertEq(logs.length, 1);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.SetCurveConfig.selector);
        assertEq(logs[0].data, abi.encode(newConfig));
    }

    function test_WhenMarketIsPaused_QueriesExactPauseTypeAndSkipsAccrual() external {
        CurveConfig memory newConfig = cfg;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        market.setPaused(PAUSE_TYPE, true);
        vm.expectCall(address(market), _pausedCall(), 1);

        _setCurveConfigAsOwner(newConfig);

        _assertCurveConfig(newConfig);
        assertEq(market.accrueInterestCalls(), 0);
    }

    function test_RevertWhen_PausedQueryReverts_BubblesAndRollsBack() external {
        CurveConfig memory newConfig = cfg;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        _mockPausedQueryRevert();
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert(_pausedQueryRevertData());
        irm.setCurveConfig(newConfig);

        _assertCurveConfig(cfg);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_PausedReturnDataIsMalformed_RollsBack() external {
        CurveConfig memory newConfig = cfg;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        vm.mockCall(address(market), _pausedCall(), hex"01");
        IRState memory stateBefore = _readIRState();

        vm.prank(OWNER);
        vm.expectRevert();
        irm.setCurveConfig(newConfig);

        _assertCurveConfig(cfg);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_AccrualRevertsAfterCallback_RollsBackNestedState() external {
        CurveConfig memory newConfig = cfg;
        newConfig.recoveryDelay += 1;
        _bindMarket();
        vm.warp(DEFAULT_NOW + 1);
        _setCurrentObservation(STRESS_PRICE);
        market.setAccrueRevertPoint(MockPegResponsiveIrmMarket.AccrueRevertPoint.AFTER_CALLBACK);
        IRState memory stateBefore = _readIRState();
        vm.expectCall(address(market), _pausedCall(), 1);
        vm.expectCall(address(market), _accrueInterestCall(), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockPegResponsiveIrmMarket.MockPegResponsiveIrmMarketAccrueReverted.selector,
                MockPegResponsiveIrmMarket.AccrueRevertPoint.AFTER_CALLBACK
            )
        );
        irm.setCurveConfig(newConfig);

        _assertCurveConfig(cfg);
        _assertIRState(stateBefore);
    }

    function test_RevertWhen_CallbackRaisesRateAboveNewMax_UsesPostCheckpointOldConfigState() external {
        CurveConfig memory newConfig = cfg;
        newConfig.stressRate = cfg.baseRate;
        newConfig.maxRate = cfg.stressRate - 1;
        _bindMarket();
        vm.warp(DEFAULT_NOW + 1);
        _setCurrentObservation(STRESS_PRICE);
        IRState memory stateBefore = _readIRState();
        assertLe(stateBefore.borrowRate, newConfig.maxRate);
        vm.expectCall(address(market), _accrueInterestCall(), 1);
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        vm.expectRevert(IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
        irm.setCurveConfig(newConfig);

        _assertCurveConfig(cfg);
        _assertIRState(stateBefore);
    }

    function test_When_CallbackLowersRateToNewMaxOrBelow_UsesPostCheckpointStateAndOldConfig() external {
        CurveConfig memory newConfig = cfg;
        newConfig.baseRate = 1;
        newConfig.stressRate = 1;
        newConfig.maxRate = (cfg.baseRate + cfg.stressRate) / 2;
        _bindMarket();
        vm.warp(DEFAULT_NOW + 100);
        IRState memory seededState = IRState({
            borrowRate: cfg.stressRate,
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
        _setCurveConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = IRState({
            borrowRate: cfg.baseRate,
            lastUpdate: uint48(block.timestamp),
            recoveryStartedAt: 0,
            stressMode: false
        });
        assertLt(expectedState.borrowRate, newConfig.maxRate);
        _assertCurveConfig(newConfig);
        _assertIRState(expectedState);
        assertEq(market.accrueInterestCalls(), 1);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.BorrowRateUpdated.selector);
        assertEq(
            logs[0].data,
            abi.encode(seededState.borrowRate, expectedState.borrowRate, RECOVERY_PRICE, uint48(block.timestamp), true)
        );
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
        _assertIrmEvent(logs[2], IPegResponsiveIrmEvents.SetCurveConfig.selector);
        assertEq(logs[2].data, abi.encode(newConfig));
    }

    function test_RevertWhen_PostCheckpointRateExceedsNewMax() external {
        CurveConfig memory newConfig = cfg;
        newConfig.maxRate = cfg.stressRate + 1;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = newConfig.maxRate + 1;
        _setIRState(seededState);

        vm.prank(OWNER);
        vm.expectRevert(IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
        irm.setCurveConfig(newConfig);

        _assertCurveConfig(cfg);
        _assertIRState(seededState);
    }

    function test_When_PostCheckpointRateEqualsNewMax_AcceptsBoundary() external {
        CurveConfig memory newConfig = cfg;
        newConfig.maxRate = cfg.stressRate + 1;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = newConfig.maxRate;
        _setIRState(seededState);

        _setCurveConfigAsOwner(newConfig);

        _assertCurveConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_WhenConfigEqualsStored_StillCheckpointsAndEmitsReplacement() external {
        _bindMarket();
        vm.expectCall(address(market), _accrueInterestCall(), 1);

        vm.recordLogs();
        _setCurveConfigAsOwner(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(market.accrueInterestCalls(), 1);
        _assertCurveConfig(cfg);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.BorrowRateUpdated.selector);
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        _assertIrmEvent(logs[2], IPegResponsiveIrmEvents.SetCurveConfig.selector);
        assertEq(logs[2].data, abi.encode(cfg));
    }

    function test_AcceptsStoredRateBelowNewBaseAndStressWithoutImmediateRepricing() external {
        CurveConfig memory newConfig = cfg;
        IRState memory seededState = _readIRState();
        seededState.borrowRate = 1;
        _setIRState(seededState);

        _setCurveConfigAsOwner(newConfig);

        assertLt(seededState.borrowRate, newConfig.baseRate);
        assertLt(seededState.borrowRate, newConfig.stressRate);
        _assertCurveConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_DoesNotReadOracleOrReevaluateStressAgainstNewThresholds() external {
        CurveConfig memory newConfig = cfg;
        newConfig.stressPrice = RECOVERY_PRICE - 1;
        IRState memory seededState = _readIRState();
        seededState.stressMode = false;
        _setIRState(seededState);
        _mockOracleReturnData(hex"01");

        _setCurveConfigAsOwner(newConfig);

        _assertCurveConfig(newConfig);
        _assertIRState(seededState);
    }

    function test_WhenRecoveryIsActive_ClearsOnlyRecoveryAndEmitsExactOrder() external {
        CurveConfig memory newConfig = cfg;
        newConfig.recoveryDelay += 1;
        IRState memory seededState =
            IRState({borrowRate: cfg.stressRate, lastUpdate: 123, recoveryStartedAt: 456, stressMode: true});
        _setIRState(seededState);

        vm.recordLogs();
        _setCurveConfigAsOwner(newConfig);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IRState memory expectedState = seededState;
        expectedState.recoveryStartedAt = 0;
        _assertCurveConfig(newConfig);
        _assertIRState(expectedState);
        assertEq(logs.length, 3);
        _assertIrmEvent(logs[0], IPegResponsiveIrmEvents.StressStateUpdated.selector);
        assertEq(logs[0].data, abi.encode(true, uint48(0), uint256(0)));
        _assertIrmEvent(logs[1], IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[1].data, abi.encode(expectedState));
        _assertIrmEvent(logs[2], IPegResponsiveIrmEvents.SetCurveConfig.selector);
        assertEq(logs[2].data, abi.encode(newConfig));
    }

    function _expectConfigRevert(CurveConfig memory invalidConfig, bytes4 selector) private {
        CurveConfig memory configBefore = _readCurveConfig();
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.prank(OWNER);
        vm.expectRevert(selector);
        irm.setCurveConfig(invalidConfig);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertCurveConfig(configBefore);
        _assertIRState(stateBefore);
    }

    function _setAndAssertConfig(CurveConfig memory newConfig) private {
        IRState memory stateBefore = _readIRState();
        _setCurveConfigAsOwner(newConfig);
        _assertCurveConfig(newConfig);
        _assertIRState(stateBefore);
    }

    function _setCurveConfigAsOwner(CurveConfig memory newConfig) private {
        vm.prank(OWNER);
        irm.setCurveConfig(newConfig);
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
