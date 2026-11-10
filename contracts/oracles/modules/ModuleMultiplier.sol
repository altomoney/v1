// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import {MultiplierNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ModuleMultiplier
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Utility contract used to scale an input by a fixed multiplier
/// @custom:audit Pending
contract ModuleMultiplier {
    error ModuleMultiplierInvalidInput();

    /// @dev 10^54 is the upper bound for the multiplier to prevent overflow and unrealistic values
    uint256 internal constant MAX_MULTIPLIER = 1e54;

    /// @notice Scales a quote amount by the multiplier defined in the node config
    /// @param quoteAmount The input amount to scale
    /// @param config Multiplier node configuration
    /// @return The `quoteAmount` scaled by `config.multiplier`
    function readMultipliedInput(uint256 quoteAmount, MultiplierNode memory config) public pure returns (uint256) {
        return quoteAmount * config.multiplier;
    }

    /// @notice Validates the multiplier node parameters during initialization or updates
    /// @dev Multiplier must be non-zero, a multiple of 10, and at most 10^54
    /// @param config Multiplier node configuration
    function _validateMultiplierNode(MultiplierNode memory config) internal pure {
        if (config.multiplier == 0 || config.multiplier > MAX_MULTIPLIER || config.multiplier % 10 != 0) {
            revert ModuleMultiplierInvalidInput();
        }
    }
}
