// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/// @title Uint128Converter
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Library for converting uint256 to uint128.
library Uint128Converter {
    error MathUtilsMaxUint128Overflow();

    /// @dev Converts a uint256 to a uint128, reverting if the value is greater than the maximum value of uint128.
    /// @param x The value to convert.
    /// @return The converted value.
    function toUint128(uint256 x) internal pure returns (uint128) {
        if (x > type(uint128).max) {
            revert MathUtilsMaxUint128Overflow();
        }

        return uint128(x);
    }
}
