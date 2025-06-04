// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";

import {AdaptiveCurveIrm} from "@alto/lending/AdaptiveCurveIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IrmCommon} from "./IrmCommon.t.sol";

contract AdaptiveCurveIrmMock is AdaptiveCurveIrm {
    constructor(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory _config, address _owner)
        AdaptiveCurveIrm(_config, _owner)
    {}

    function lastUpdate() external view returns (uint48) {
        return irState.lastUpdate;
    }

    function rateAtTarget() external view returns (int256) {
        return irState.rateAtTarget;
    }

    function validateConfig(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory _config) public pure {
        _validateConfig(_config);
    }
}

contract MockMarket {
    function accrueInterest() external {}
}

contract AdaptiveCurveIrmTest is IrmCommon {
    using FixedPointMath for uint256;

    AdaptiveCurveIrm public adaptiveCurveIrm;

    MockMarket mockMarket = new MockMarket();

    function _createAdaptiveCurveIrm(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig)
        internal
        returns (AdaptiveCurveIrmMock)
    {
        AdaptiveCurveIrmMock newAdaptiveCurveIrm = new AdaptiveCurveIrmMock(irmConfig, address(this));
        newAdaptiveCurveIrm.setMarket(address(mockMarket));
        return newAdaptiveCurveIrm;
    }

    function _createAdaptiveCurveIrmSample(bool setMarket) internal returns (AdaptiveCurveIrmMock) {
        AdaptiveCurveIrmMock newAdaptiveCurveIrm = new AdaptiveCurveIrmMock(
            AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                curveSteepness: 4 ether,
                adjustmentSpeed: 50 ether / YEAR,
                targetUtilization: 0.8 ether,
                initialRateAtTarget: 0.04 ether / YEAR,
                minRateAtTarget: 0.001e18 / YEAR,
                maxRateAtTarget: 2 ether / YEAR
            }),
            address(this)
        );
        if (setMarket) {
            newAdaptiveCurveIrm.setMarket(address(mockMarket));
        }
        return newAdaptiveCurveIrm;
    }

    function testSetIrmConfigViaConstuctor(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) external {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock newAdaptiveCurveIrm = _createAdaptiveCurveIrm(irmConfig);

        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = newAdaptiveCurveIrm.irmConfig();

        assertEq(curveSteepness, irmConfig.curveSteepness);
        assertEq(adjustmentSpeed, irmConfig.adjustmentSpeed);
        assertEq(targetUtilization, irmConfig.targetUtilization);
        assertEq(initialRateAtTarget, irmConfig.initialRateAtTarget);
        assertEq(minRateAtTarget, irmConfig.minRateAtTarget);
        assertEq(maxRateAtTarget, irmConfig.maxRateAtTarget);
    }

    function testSetIrmConfigViaConstuctorInvalid(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) external {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfigCopy = irmConfig;
        irmConfigCopy.curveSteepness = 1.01e18 - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new AdaptiveCurveIrmMock(irmConfigCopy, address(this));
        irmConfigCopy.curveSteepness = irmConfig.curveSteepness;

        irmConfigCopy.adjustmentSpeed = 2e18 / YEAR - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new AdaptiveCurveIrmMock(irmConfigCopy, address(this));
        irmConfigCopy.adjustmentSpeed = irmConfig.adjustmentSpeed;

        irmConfigCopy.targetUtilization = 0;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new AdaptiveCurveIrmMock(irmConfigCopy, address(this));
        irmConfigCopy.targetUtilization = irmConfig.targetUtilization;

        irmConfigCopy.minRateAtTarget = 0.001e18 / YEAR - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new AdaptiveCurveIrmMock(irmConfigCopy, address(this));
        irmConfigCopy.minRateAtTarget = irmConfig.minRateAtTarget;

        irmConfigCopy.maxRateAtTarget = 0.001e18 / YEAR - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new AdaptiveCurveIrmMock(irmConfigCopy, address(this));
        irmConfigCopy.maxRateAtTarget = irmConfig.maxRateAtTarget;

        irmConfigCopy.initialRateAtTarget = irmConfig.minRateAtTarget - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new AdaptiveCurveIrmMock(irmConfigCopy, address(this));
        irmConfigCopy.initialRateAtTarget = irmConfig.initialRateAtTarget;
    }

    function testSetMarket() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(false);

        assertEq(irm.lastUpdate(), 0);
        irm.setMarket(address(1));
        assertEq(irm.market(), address(1));
        assertEq(irm.lastUpdate(), block.timestamp);
    }

    function testSetMarketRewrite() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(false);

        irm.setMarket(address(1));
        vm.expectRevert(IIrm.Alto_IrmMarketAlreadySet.selector);
        irm.setMarket(address(2));
    }

    function testSetIrmConfig(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) external {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irm.setIrmConfig(irmConfig);
        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = irm.irmConfig();

        assertEq(curveSteepness, irmConfig.curveSteepness);
        assertEq(adjustmentSpeed, irmConfig.adjustmentSpeed);
        assertEq(targetUtilization, irmConfig.targetUtilization);
        assertEq(initialRateAtTarget, irmConfig.initialRateAtTarget);
        assertEq(minRateAtTarget, irmConfig.minRateAtTarget);
        assertEq(maxRateAtTarget, irmConfig.maxRateAtTarget);
    }

    function testSetIrmConfigInvalidCurveSteepness(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) external {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irmConfig.curveSteepness = 1.01e18 - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        irm.validateConfig(irmConfig);
    }

    function testSetIrmConfigInvalidAdjustmentSpeed(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig)
        external
    {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irmConfig.adjustmentSpeed = 2e18 / YEAR - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        irm.validateConfig(irmConfig);
    }

    function testSetIrmConfigInvalidTargetUtilization(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig)
        external
    {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irmConfig.targetUtilization = 0;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        irm.validateConfig(irmConfig);
    }

    function testSetIrmConfigInvalidMinRateAtTarget(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig)
        external
    {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irmConfig.minRateAtTarget = 0.001e18 / YEAR - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        irm.validateConfig(irmConfig);
    }

    function testSetIrmConfigInvalidMaxRateAtTarget(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig)
        external
    {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irmConfig.maxRateAtTarget = 10e18 / YEAR + 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        irm.validateConfig(irmConfig);
    }

    function testSetIrmConfigInvalidInitialRateAtTarget(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig)
        external
    {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        irmConfig.initialRateAtTarget = irmConfig.minRateAtTarget - 1;
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        irm.validateConfig(irmConfig);
    }

    function testSetIrmConfigEvent(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) external {
        _fuzzAdaptiveCurveConfig(irmConfig);

        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        vm.expectEmit(true, true, true, true, address(irm));
        emit AdaptiveCurveIrm.SetIrmConfig(irmConfig);
        irm.setIrmConfig(irmConfig);
    }

    function testSetIrmConfigMarketUnset(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(false);

        vm.expectRevert(IIrm.Alto_IrmMarketNotSet.selector);
        irm.setIrmConfig(irmConfig);
    }

    function testInterestRateView() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        uint256 firstBlockTimestamp = block.timestamp;
        assertEq(irm.lastUpdate(), firstBlockTimestamp);

        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = irm.irmConfig();

        vm.warp(block.timestamp + 1 days);
        (uint256 interest, uint256 borrowRate) = irm.updateInterestRateView(0, 0);
        assertEq(interest, 0);
        assertEq(irm.rateAtTarget(), initialRateAtTarget);
        assertEq(irm.lastUpdate(), firstBlockTimestamp);
    }

    function testUnsetMarketInterestRateViewRevert() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(false);

        vm.expectRevert(IIrm.Alto_IrmMarketNotSet.selector);
        irm.updateInterestRateView(0, 0);
    }

    function _getAccruedInterest(uint256 borrowedAmount, uint256 borrowRate, uint256 time)
        internal
        view
        returns (uint256)
    {
        return uint256(borrowedAmount).multiplyWithPrecision(borrowRate.calculateCompoundInterest(time));
    }

    function testInterestRate() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        assertEq(irm.lastUpdate(), block.timestamp);

        vm.warp(block.timestamp + 1 days);

        vm.prank(address(irm.market()));
        (uint256 interest, uint256 borrowRate) = irm.updateInterestRate(0, 1000 ether);
        uint256 expectedBorrowRate = 296494587;
        assertEq(interest, _getAccruedInterest(1000 ether, expectedBorrowRate, 1 days));
        assertEq(borrowRate, expectedBorrowRate);
        assertEq(irm.lastUpdate(), block.timestamp);
    }

    function testUnsetMarketInterestRateRevert() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(false);
        irm.setMarket(address(this));

        vm.prank(address(mockMarket));
        vm.expectRevert(IIrm.Alto_IrmUnauthorized.selector);
        irm.updateInterestRate(0, 0);
    }

    function testNonMarketInterestRateRevert() external {
        AdaptiveCurveIrmMock irm = _createAdaptiveCurveIrmSample(true);

        vm.expectRevert(IIrm.Alto_IrmUnauthorized.selector);
        irm.updateInterestRate(0, 0);
    }
}
