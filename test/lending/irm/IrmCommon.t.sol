// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";

import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {ERC20Mock} from "../../helpers/ERC20Mock.sol";

contract IrmCommon is Test {
    using FixedPointMath for uint256;

    ERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;

    address internal immutable USER = makeAddr("User");

    uint256 internal constant LTV = 0.75 ether;

    int256 internal constant YEAR = int256(365 days);

    uint256 constant MIN_AMOUNT = 1000;
    uint256 constant MAX_AMOUNT = 2 ** 64;

    function setUp() public {
        borrowToken = new ERC20Mock("borrow", "B");
        collateralToken = new ERC20Mock("collateral", "C");

        deal(address(borrowToken), address(this), type(uint256).max);
        deal(address(collateralToken), address(this), type(uint256).max);
    }

    function _fuzzAdaptiveCurveConfig(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig) internal pure {
        irmConfig.curveSteepness = bound(irmConfig.curveSteepness, 1.01e18, 100e18);
        irmConfig.adjustmentSpeed = bound(irmConfig.adjustmentSpeed, 2e18 / YEAR, 1000e18 / YEAR);
        irmConfig.targetUtilization = bound(irmConfig.targetUtilization, 1, 1e18);
        int256 minRate = bound(irmConfig.minRateAtTarget, 0.001e18 / YEAR, 10e18 / YEAR);
        int256 maxRate = bound(irmConfig.maxRateAtTarget, 0.001e18 / YEAR, 10e18 / YEAR);

        // Ensure max is not less than min
        if (maxRate < minRate) {
            (minRate, maxRate) = (maxRate, minRate);
        }
        irmConfig.minRateAtTarget = minRate;
        irmConfig.maxRateAtTarget = maxRate;

        irmConfig.initialRateAtTarget =
            bound(irmConfig.initialRateAtTarget, irmConfig.minRateAtTarget, irmConfig.maxRateAtTarget);
    }
}
