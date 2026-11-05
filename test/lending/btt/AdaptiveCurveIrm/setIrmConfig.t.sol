// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketBase, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {AdaptiveCurveIrmCommon} from "./AdaptiveCurveIrmCommon.t.sol";

contract AdaptiveCurveIrmSetIrmConfigTest is AdaptiveCurveIrmCommon {
    function test_RevertWhen_CallerIsNotOwner_BeforeMarketAndConfigurationChecks() public {
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory invalidConfig = _invalidCurveSteepnessConfig();
        _expectUnauthorized(invalidConfig);
        _assertState(0, 0);

        _bindMarket();
        _mockPauseQueryFailure();
        _expectUnauthorized(invalidConfig);
        _assertUnchanged();
    }

    function test_RevertWhen_MarketIsUnset_BeforeConfigurationValidation() public {
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory invalidConfig = _invalidCurveSteepnessConfig();
        vm.prank(OWNER);
        vm.expectRevert(IIrm.IrmMarketNotSet.selector);
        irm.setIrmConfig(invalidConfig);
        _assertState(0, 0);
        _assertConfig(config);
    }

    function test_RevertWhen_AnyConfigurationFieldIsInvalid_WhilePaused() public {
        _bindMarket();
        _pauseMarket();
        vm.warp(START + 100_000);
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases = _invalidConfigs();
        for (uint256 i; i < cases.length; ++i) {
            vm.prank(OWNER);
            vm.expectRevert(IIrm.IrmInvalidParams.selector);
            irm.setIrmConfig(cases[i]);
            _assertUnchanged();
        }
    }

    function test_RevertWhen_AnyConfigurationFieldIsInvalid_RollsBackActiveAccrual() public {
        _bindMarket();
        vm.warp(START + 100_000);
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases = _invalidConfigs();
        for (uint256 i; i < cases.length; ++i) {
            vm.expectCall(address(market), abi.encodeCall(IMarketBase.accrueInterest, ()));
            vm.prank(OWNER);
            vm.expectRevert(IIrm.IrmInvalidParams.selector);
            irm.setIrmConfig(cases[i]);
            _assertUnchanged();
        }
    }

    function test_WhenMarketIsActive_AccruesOldConfigurationThenResetsRateAndEmits() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(_newConfig(), false);
    }

    function test_WhenActiveAfterAdaptation_AccruesAdaptedRateThenResetsToNewInitialRate() public {
        _bindMarket();
        vm.warp(START + 100_000);
        vm.prank(address(market));
        irm.updateInterestRate(1000 ether, 900 ether);
        _assertState(1_051_250_000, uint48(START + 100_000));
        assertGt(_readState().rateAtTarget, INITIAL_RATE);

        // The market fixture stays at target utilization, so setter accrual
        // uses the adapted rate without further adaptation under the old config.
        _assertMarketBalances(1000 ether, 800 ether);
        vm.warp(START + 200_000);
        _assertSuccessfulChange(_newConfig(), false);
    }

    function test_WhenMarketIsPaused_SkipsAccrualAndPreservesTimestamp() public {
        _bindMarket();
        _pauseMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(_newConfig(), true);
    }

    function test_WhenConfigurationIsAtInclusiveBoundaries_AcceptsEveryBoundary() public {
        _bindMarket();
        _pauseMarket();
        vm.warp(START + 100_000);
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases = _boundaryConfigs();
        for (uint256 i; i < cases.length; ++i) {
            _assertSuccessfulChange(cases[i], true);
        }
    }

    function test_WhenConfigurationIsUnchanged_StillAccruesAndEmits() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(config, false);
    }

    function test_WhenPausedAfterAdaptation_ResetsToInitialRateEvenForSameConfiguration() public {
        _bindMarket();
        vm.warp(START + 100_000);
        vm.prank(address(market));
        irm.updateInterestRate(1000 ether, 900 ether);
        _assertState(1_051_250_000, uint48(START + 100_000));

        _pauseMarket();
        vm.warp(START + 200_000);
        _assertSuccessfulChange(config, true);
    }

    function test_RevertWhen_PauseQueryFails_BeforeConfigurationValidation() public {
        _bindMarket();
        _mockPauseQueryFailure();
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory invalidConfig = _invalidCurveSteepnessConfig();
        vm.prank(OWNER);
        vm.expectRevert(MarketCallFailed.selector);
        irm.setIrmConfig(invalidConfig);
        _assertUnchanged();
    }

    function test_RevertWhen_AccrualFails_RollsBackCallbackBeforeConfigurationValidation() public {
        _bindMarket();
        (uint256 supply, uint256 borrowed) = _prepareMarketAccrualOverflow();
        vm.warp(START + 100_000);
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory invalidConfig = _invalidCurveSteepnessConfig();
        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (supply, borrowed)), 1);
        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        irm.setIrmConfig(invalidConfig);
        _assertState(INITIAL_RATE, uint48(START));
        _assertConfig(config);
        _assertMarketBalances(supply, borrowed);
    }

    function _expectUnauthorized(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory candidate) internal {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        irm.setIrmConfig(candidate);
        _assertConfig(config);
    }

    function _newConfig() internal pure returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory candidate) {
        candidate = AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 6e18,
            adjustmentSpeed: 2e12,
            targetUtilization: 0.75e18,
            initialRateAtTarget: 2e9,
            minRateAtTarget: 0.002e18 / YEAR,
            maxRateAtTarget: 3e18 / YEAR
        });
    }

    function _assertUnchanged() internal view {
        _assertState(INITIAL_RATE, uint48(START));
        _assertConfig(config);
        assertEq(irm.market(), address(market));
        assertEq(irm.owner(), OWNER);
        _assertMarketBalances(1000 ether, 800 ether);
    }

    function _assertSuccessfulChange(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory candidate, bool paused) internal {
        AdaptiveCurveIrm.IRState memory beforeState = _readState();
        uint48 timestamp = paused ? beforeState.lastUpdate : uint48(block.timestamp);
        uint256 interest = paused
            ? 0
            : _expectedInterest(800 ether, uint256(beforeState.rateAtTarget), block.timestamp - beforeState.lastUpdate);
        vm.expectCall(address(market), abi.encodeCall(IPausable.paused, (PAUSE_TYPE)));
        if (!paused) vm.expectCall(address(market), abi.encodeCall(IMarketBase.accrueInterest, ()), 1);
        vm.recordLogs();
        vm.prank(OWNER);
        irm.setIrmConfig(candidate);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertConfig(candidate);
        _assertState(candidate.initialRateAtTarget, timestamp);
        assertEq(irm.owner(), OWNER);
        assertEq(irm.market(), address(market));
        _assertMarketBalances(1000 ether + interest, 800 ether + interest);
        assertEq(logs.length, paused ? 2 : 4);
        if (!paused) {
            _assertStateLog(logs[0], beforeState.rateAtTarget, timestamp);
            assertEq(logs[1].emitter, address(market));
            assertEq(logs[1].topics.length, 1);
            assertEq(logs[1].topics[0], IMarketEvents.AccrueInterest.selector);
            assertEq(
                logs[1].data,
                abi.encode(
                    uint256(beforeState.rateAtTarget),
                    interest,
                    uint128(800 ether + interest),
                    uint128(1000 ether + interest)
                )
            );
        }
        _assertStateLog(logs[logs.length - 2], candidate.initialRateAtTarget, timestamp);
        Vm.Log memory configLog = logs[logs.length - 1];
        assertEq(configLog.emitter, address(irm));
        assertEq(configLog.topics.length, 1);
        assertEq(configLog.topics[0], AdaptiveCurveIrm.SetIrmConfig.selector);
        assertEq(configLog.data, abi.encode(candidate));
    }
}
