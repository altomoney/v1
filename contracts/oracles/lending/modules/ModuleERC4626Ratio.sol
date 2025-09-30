// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title Module ERC4626 Ratio
/// @author Pearl Labs
abstract contract ModuleERC4626Ratio {
    error ModuleERC4626RatioInvalidInput();

    uint256 public constant SECONDS_PER_YEAR = 365.2425 days;

    /// @notice Return the current capped ratio
    function readLatestRatio(
        uint256 quoteAmount,
        int256 latestRatio,
        uint256 _initialRatio,
        uint256 _initialTimestamp,
        uint256 _yearlyGrowthBps
    ) external view returns (int256) {
        int256 currentRatio = latestRatio;
        if (currentRatio <= 0) return 0;

        int256 maxRatio = int256(_computeMaxRatio(_initialRatio, _initialTimestamp, _yearlyGrowthBps));

        if (currentRatio > maxRatio) {
            return maxRatio;
        } else {
            return currentRatio;
        }
    }

    /// @notice Computes allowed max ratio growth given initial data and elapsed time
    function _computeMaxRatio(uint256 _initialRatio, uint256 _initialTimestamp, uint256 _yearlyGrowthBps)
        internal
        view
        returns (uint256)
    {
        uint256 timePassed = block.timestamp - _initialTimestamp;
        uint256 growthPerSecond = (_initialRatio * _yearlyGrowthBps) / MATH_PRECISION / SECONDS_PER_YEAR;
        return _initialRatio + growthPerSecond * timePassed;
    }

    /// @notice Set parameters for ratio snapshot and growth limits
    function _validateERC4626RatioParams(uint256 _initialRatio, uint256 _initialTimestamp, uint256 _yearlyGrowthBps)
        internal
    {
        if (_initialRatio <= 0) {
            revert ModuleERC4626RatioInvalidInput();
        }
        if (_initialTimestamp >= block.timestamp) {
            revert ModuleERC4626RatioInvalidInput();
        }
        if (_yearlyGrowthBps == 0) {
            revert ModuleERC4626RatioInvalidInput();
        }
    }
}
