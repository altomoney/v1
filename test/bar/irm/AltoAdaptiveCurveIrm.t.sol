// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoAdaptiveCurveIrm} from "../../../contracts/bar/irm/AltoAdaptiveCurveIrm.sol";
import {WAD_INT, MathLib} from "../../../contracts/bar/irm/libraries/MathLib.sol";
import {console} from "forge-std/console.sol";

contract AltoAdaptiveCurveIrmTest is Test {
    using MathLib for int256;

    AltoAdaptiveCurveIrm internal altoAdaptiveCurveIrm;

    function setUp() public {
        altoAdaptiveCurveIrm = new AltoAdaptiveCurveIrm();
    }

    function test_constructor() external {
        new AltoAdaptiveCurveIrm();
    }

    function _getDefaultIrmConfiguration(int256 _initialRateAtTarget) internal pure returns (AltoAdaptiveCurveIrm.IrmConfiguration memory) {
        // Default values from ConstantsLib: https://github.com/morpho-org/morpho-blue-irm/blob/0e99e647c9bd6d3207f450144b6053cf807fa8c4/src/adaptive-curve-irm/libraries/ConstantsLib.sol#L7
        return AltoAdaptiveCurveIrm.IrmConfiguration({
            targetUtilization: 0.9 ether,
            initialRateAtTarget: _initialRateAtTarget / int256(365 days),
            adjustmentSpeed: 50 ether / int256(365 days),
            minRateAtTarget: 0.001 ether / int256(365 days),
            maxRateAtTarget: 2.0 ether / int256(365 days),
            curveSteepness: 4 ether
        });
    }

    function test_getBorrowRate_valid(int256 _initialRateAtTarget) external {
        int256 initialRateAtTarget = bound(_initialRateAtTarget, 0.000001 ether, type(int128).max);
        AltoAdaptiveCurveIrm.IrmConfiguration memory irmConfiguration = _getDefaultIrmConfiguration(initialRateAtTarget);

        AltoAdaptiveCurveIrm.IrmMarketData memory irmMarketData = AltoAdaptiveCurveIrm.IrmMarketData({
            totalSupplyAssets: 1 ether,
            totalBorrowAssets: 1 ether,
            elapsedSeconds: 0,
            currentRateAtTarget: 0 ether
        });

        (uint256 avgRate, int256 endRateAtTarget) = altoAdaptiveCurveIrm.getBorrowRate(irmMarketData, irmConfiguration);

        assertEq(avgRate, uint256(initialRateAtTarget / int256(365 days) * 4));
        assertEq(endRateAtTarget, initialRateAtTarget / int256(365 days));
    }
}
