// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title Module ERC4626 Ratio
/// @author Pearl Labs
/// @notice Module contract that is used to read from ERC4626 vaults
/// @dev This contract caps the ratio of the ERC4626 vault to a certain growth rate to prevent impact if underlying erc4626 is manipulated
contract ModuleERC4626Ratio {
    error ModuleERC4626RatioInvalidInput();

    uint256 public constant SECONDS_PER_YEAR = 365.2425 days;

    /// @notice Return the current capped ratio
    /// @param latestRatio The latest ratio of the ERC4626 vault
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @return The current ratio. If the ratio is greater than the maximum allowed ratio, the maximum allowed ratio is returned.
    function readLatestRatio(uint256 latestRatio, ERC4626RatioNode memory _erc4626RatioNode)
        external
        view
        returns (uint256)
    {
        uint256 currentRatio = latestRatio;
        if (currentRatio == 0) return 0;

        uint256 maxRatio = _computeMaxRatio(_erc4626RatioNode);

        if (currentRatio > maxRatio) {
            return maxRatio;
        } else {
            return currentRatio;
        }
    }

    /// @notice Computes allowed max ratio growth given initial data and elapsed time
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @return The maximum allowed ratio
    function _computeMaxRatio(ERC4626RatioNode memory _erc4626RatioNode) internal view returns (uint256) {
        uint256 timePassed = block.timestamp - _erc4626RatioNode.initialTimestamp;
        uint256 maxGrowthPerYear = _erc4626RatioNode.initialRatio * _erc4626RatioNode.maxYearlyGrowthRatioWad;
        uint256 maxAllowedGrowthRatio = maxGrowthPerYear * timePassed / MATH_PRECISION / SECONDS_PER_YEAR;
        return _erc4626RatioNode.initialRatio + maxAllowedGrowthRatio;
    }

    /// @notice Validates the parameters set for ratio snapshot and growth limits during initialization or updates
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    function _validateERC4626RatioParams(ERC4626RatioNode memory _erc4626RatioNode) internal view {
        if (_erc4626RatioNode.initialRatio == 0) {
            revert ModuleERC4626RatioInvalidInput();
        }
        if (_erc4626RatioNode.initialTimestamp > block.timestamp) {
            revert ModuleERC4626RatioInvalidInput();
        }
        if (_erc4626RatioNode.maxYearlyGrowthRatioWad == 0) {
            revert ModuleERC4626RatioInvalidInput();
        }
    }
}
