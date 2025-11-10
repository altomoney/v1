// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title Module ERC4626 Ratio
/// @author Pearl Labs
/// @notice Module contract that is used to read from ERC4626 vaults
/// @dev This contract caps the ratio of the ERC4626 vault to a certain growth rate to prevent impact if underlying erc4626 is manipulated
contract ModuleERC4626Ratio {
    error ModuleERC4626RatioInvalidInput();

    uint256 public constant SECONDS_PER_YEAR = 365.2425 days;

    /// @notice Return the current capped ratio
    /// @param latestRatio The latest ratio of the ERC4626 vault
    /// @param _initialRatio The initial ratio of the ERC4626 vault
    /// @param _initialTimestamp The initial timestamp of the ERC4626 vault when the initial ratio was set
    /// @param _maxYearlyGrowthRatioWad The maximum yearly growth ratio of the ERC4626 vault defined in wad. (1e18 = 100%)
    /// @return The current ratio. If the ratio is greater than the maximum allowed ratio, the maximum allowed ratio is returned.
    function readLatestRatio(
        uint256 latestRatio,
        uint256 _initialRatio,
        uint256 _initialTimestamp,
        uint256 _maxYearlyGrowthRatioWad
    ) external view returns (uint256) {
        uint256 currentRatio = latestRatio;
        if (currentRatio == 0) return 0;

        uint256 maxRatio = _computeMaxRatio(_initialRatio, _initialTimestamp, _maxYearlyGrowthRatioWad);

        if (currentRatio > maxRatio) {
            return maxRatio;
        } else {
            return currentRatio;
        }
    }

    /// @notice Computes allowed max ratio growth given initial data and elapsed time
    /// @param _initialRatio The initial ratio of the ERC4626 vault
    /// @param _initialTimestamp The initial timestamp of the ERC4626 vault when the initial ratio was set
    /// @param _maxYearlyGrowthRatioWad The maximum yearly growth ratio of the ERC4626 vault defined in wad. (1e18 = 100%)
    /// @return The maximum allowed ratio
    function _computeMaxRatio(uint256 _initialRatio, uint256 _initialTimestamp, uint256 _maxYearlyGrowthRatioWad)
        internal
        view
        returns (uint256)
    {
        uint256 timePassed = block.timestamp - _initialTimestamp;
        uint256 maxGrowthPerYear = _initialRatio * _maxYearlyGrowthRatioWad;
        uint256 maxAllowedGrowthRatio = maxGrowthPerYear * timePassed / MATH_PRECISION / SECONDS_PER_YEAR;
        return _initialRatio + maxAllowedGrowthRatio;
    }

    /// @notice Validates the parameters set for ratio snapshot and growth limits during initialization or updates
    /// @param _initialRatio The initial ratio of the ERC4626 vault
    /// @param _initialTimestamp The initial timestamp of the ERC4626 vault when the initial ratio was set
    /// @param _maxYearlyGrowthRatioWad The maximum yearly growth ratio of the ERC4626 vault defined in wad. (1e18 = 100%)
    function _validateERC4626RatioParams(
        uint256 _initialRatio,
        uint256 _initialTimestamp,
        uint256 _maxYearlyGrowthRatioWad
    ) internal view {
        if (_initialRatio == 0) {
            revert ModuleERC4626RatioInvalidInput();
        }
        if (_initialTimestamp > block.timestamp) {
            revert ModuleERC4626RatioInvalidInput();
        }
        if (_maxYearlyGrowthRatioWad == 0) {
            revert ModuleERC4626RatioInvalidInput();
        }
    }
}
