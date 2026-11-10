// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {BaseMarketInitParams, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {MockMarket} from "@alto-test/helpers/MockMarket.sol";

abstract contract AdaptiveCurveIrmCommon is Test {
    using FixedPointMath for uint256;

    error MarketCallFailed();

    address internal constant OWNER = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);
    uint256 internal constant START = 1_000_000;
    int256 internal constant YEAR = 365 days;
    int256 internal constant INITIAL_RATE = 1e9;

    AdaptiveCurveIrm internal irm;
    AdaptiveCurveIrm.AdaptiveCurveIrmConfig internal config;
    MockMarket internal market;

    function setUp() public virtual {
        vm.warp(START);
        config = _defaultConfig();
        irm = new AdaptiveCurveIrm(config, OWNER);
        market = new MockMarket();
        market.initialize(
            BaseMarketInitParams({
                borrowToken: address(0xB001),
                collateralToken: address(0xC011),
                irm: address(0),
                owner: OWNER,
                emergencyAdmin: OWNER,
                oracle: address(0x0A11),
                maxLtv: 0.75e18,
                feeRecipient: OWNER,
                liquidationEngine: address(0)
            }),
            0
        );
        market.modifyTotalSupply(1000 ether);
        market.modifyTotalBorrowed(800 ether);
    }

    function _defaultConfig() internal pure returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory) {
        return AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 4e18,
            adjustmentSpeed: 1e12,
            targetUtilization: 0.8e18,
            initialRateAtTarget: INITIAL_RATE,
            minRateAtTarget: 0.001e18 / YEAR,
            maxRateAtTarget: 2e18 / YEAR
        });
    }

    function _bindMarket() internal {
        vm.prank(OWNER);
        market.setIrm(address(irm), true);
    }

    function _pauseMarket() internal {
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);
        vm.expectCall(address(market), abi.encodeCall(IMarketBase.accrueInterest, ()), 0);
    }

    function _mockPauseQueryFailure() internal {
        vm.mockCallRevert(
            address(market),
            abi.encodeCall(IPausable.paused, (PAUSE_TYPE)),
            abi.encodeWithSelector(MarketCallFailed.selector)
        );
    }

    /// @dev Interest fits uint128 and the supply addition succeeds, but adding
    /// it to saturated borrowed assets reverts after the real IRM callback.
    function _prepareMarketAccrualOverflow() internal returns (uint256 supply, uint256 borrowed) {
        borrowed = type(uint128).max;
        supply = borrowed * 9 / 10;
        market.modifyTotalSupply(supply - 1000 ether);
        market.modifyTotalBorrowed(borrowed - 800 ether);
    }

    function _assertMarketBalances(uint256 expectedSupply, uint256 expectedBorrowed) internal view {
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        (uint128 borrowedAssets, uint128 borrowedShares) = market.totalBorrowed();
        assertEq(supplyAssets, expectedSupply, "market supply assets");
        assertEq(borrowedAssets, expectedBorrowed, "market borrowed assets");
        assertEq(supplyShares, 0, "market supply shares");
        assertEq(borrowedShares, 0, "market borrowed shares");
    }

    function _readState() internal view returns (AdaptiveCurveIrm.IRState memory state) {
        (state.rateAtTarget, state.lastUpdate) = irm.irState();
    }

    function _assertState(int256 rate, uint48 timestamp) internal view {
        AdaptiveCurveIrm.IRState memory state = _readState();
        assertEq(state.rateAtTarget, rate, "rateAtTarget");
        assertEq(state.lastUpdate, timestamp, "lastUpdate");
    }

    function _assertConfig(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory expected) internal view {
        (int256 steepness, int256 speed, int256 utilization, int256 initialRate, int256 minRate, int256 maxRate) =
            irm.irmConfig();
        assertEq(steepness, expected.curveSteepness, "curveSteepness");
        assertEq(speed, expected.adjustmentSpeed, "adjustmentSpeed");
        assertEq(utilization, expected.targetUtilization, "targetUtilization");
        assertEq(initialRate, expected.initialRateAtTarget, "initialRateAtTarget");
        assertEq(minRate, expected.minRateAtTarget, "minRateAtTarget");
        assertEq(maxRate, expected.maxRateAtTarget, "maxRateAtTarget");
    }

    function _assertStateLog(Vm.Log memory entry, int256 rate, uint48 timestamp) internal view {
        assertEq(entry.emitter, address(irm));
        assertEq(entry.topics.length, 1);
        assertEq(entry.topics[0], AdaptiveCurveIrm.IRStateUpdated.selector);
        assertEq(entry.data, abi.encode(AdaptiveCurveIrm.IRState(rate, timestamp)));
    }

    function _expectedInterest(uint256 debt, uint256 rate, uint256 elapsed) internal pure returns (uint256) {
        return debt.multiplyWithPrecision(rate.calculateCompoundInterest(elapsed));
    }

    /// @dev Invalid inputs shared by the constructor and setter specs.
    function _invalidConfigs() internal pure returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases) {
        cases = _defaultConfigs(14);

        cases[0] = _invalidCurveSteepnessConfig();
        cases[1].curveSteepness = 100e18 + 1;
        cases[2].adjustmentSpeed = 2e18 / YEAR - 1;
        cases[3].adjustmentSpeed = 1000e18 / YEAR + 1;
        cases[4].targetUtilization = 0;
        cases[5].targetUtilization = 1e18 + 1;
        cases[6].initialRateAtTarget = cases[6].minRateAtTarget - 1;
        cases[7].initialRateAtTarget = cases[7].maxRateAtTarget + 1;
        cases[8].minRateAtTarget = 0.001e18 / YEAR - 1;
        cases[9] = _equalRatesConfig(10e18 / YEAR + 1);
        cases[10].maxRateAtTarget = 0.001e18 / YEAR - 1;
        cases[11].maxRateAtTarget = 10e18 / YEAR + 1;
        cases[12].minRateAtTarget = cases[12].maxRateAtTarget + 1;
        cases[13].targetUtilization = -1;
    }

    /// @dev Inclusive boundaries shared by the constructor and setter specs.
    function _boundaryConfigs() internal pure returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases) {
        cases = _defaultConfigs(8);

        cases[0].curveSteepness = 1.01e18;
        cases[1].curveSteepness = 100e18;
        cases[2].adjustmentSpeed = 2e18 / YEAR;
        cases[3].adjustmentSpeed = 1000e18 / YEAR;
        cases[4].targetUtilization = 1;
        cases[5].targetUtilization = 1e18;
        cases[6] = _equalRatesConfig(0.001e18 / YEAR);
        cases[7] = _equalRatesConfig(10e18 / YEAR);
    }

    function _invalidCurveSteepnessConfig()
        internal
        pure
        returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory candidate)
    {
        candidate = _defaultConfig();
        candidate.curveSteepness = 1.01e18 - 1;
    }

    function _equalRatesConfig(int256 rate)
        internal
        pure
        returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory candidate)
    {
        candidate = _defaultConfig();
        candidate.minRateAtTarget = rate;
        candidate.initialRateAtTarget = rate;
        candidate.maxRateAtTarget = rate;
    }

    function _defaultConfigs(uint256 count)
        internal
        pure
        returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases)
    {
        cases = new AdaptiveCurveIrm.AdaptiveCurveIrmConfig[](count);
        for (uint256 i; i < count; ++i) {
            // Allocate each configuration separately so edits cannot affect another case.
            cases[i] = _defaultConfig();
        }
    }
}
