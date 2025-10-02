// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

library OracleValidation {
    error OracleValidationZeroPrice();

    /// @notice Checks if the price from two sources is within the allowed deviation
    /// @param price1 The price from first source
    /// @param price2 The price from second source
    /// @dev this function assumes that price of two sources is in the same decimals
    /// @return True if the price from two sources is within the allowed deviation, false otherwise
    function isPriceWithinAllowedDeviation(uint256 price1, uint256 price2, uint256 maxAllowedDeviation)
        internal
        pure
        returns (bool)
    {
        if (price1 == 0 || price2 == 0) {
            revert OracleValidationZeroPrice();
        }
        uint256 deviation;
        if (price1 > price2) {
            // using the minimum of two as denominator in deviation so that we don't underestimate the deviation
            deviation = FixedPointMath.divideWithPrecisionUp(price1 - price2, price2);
        } else {
            deviation = FixedPointMath.divideWithPrecisionUp(price2 - price1, price1);
        }
        return deviation <= maxAllowedDeviation;
    }
}
