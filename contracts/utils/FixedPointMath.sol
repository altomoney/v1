// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

uint256 constant MATH_PRECISION = 1e18;

/// @title FixedPointMath
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Library for fixed point arithmetic.
library FixedPointMath {
    /// @dev Multiplies two numbers and divides by MATH_PRECISION, rounding down.
    function multiplyWithPrecision(uint256 multiplicand, uint256 multiplier) internal pure returns (uint256) {
        return (multiplicand * multiplier) / MATH_PRECISION;
    }

    /// @dev Multiplies two numbers and divides by MATH_PRECISION, rounding up.
    function multiplyWithPrecisionUp(uint256 multiplicand, uint256 multiplier) internal pure returns (uint256) {
        return Math.ceilDiv(multiplicand * multiplier, MATH_PRECISION);
    }

    /// @dev Divides a number by another using MATH_PRECISION, rounding up.
    function divideWithPrecisionUp(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return Math.ceilDiv(numerator * MATH_PRECISION, denominator);
    }

    /// @dev Divides a number by another using MATH_PRECISION, rounding down.
    function divideWithPrecisionDown(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return (numerator * MATH_PRECISION) / denominator;
    }

    /// @dev Multiplies numerator by multiplier and divides by denominator rounding division result up or down based on roundUp parameter.
    /// @dev numerator * multiplier / denominator rounding division result.
    function divideWithRounding(uint256 numerator, uint256 multiplier, uint256 denominator, bool roundUp)
        internal
        pure
        returns (uint256)
    {
        if (roundUp) {
            return Math.ceilDiv(numerator * multiplier, denominator);
        }
        return (numerator * multiplier) / denominator;
    }

    /// @dev Multiplies numerator by multiplier and divides by denominator rounding division result up or down based on half up rule.
    /// @dev numerator * multiplier / denominator rounding division result.
    function divideWithRoundingHalfUp(uint256 numerator, uint256 multiplier, uint256 denominator)
        internal
        pure
        returns (uint256)
    {
        return (numerator * multiplier + denominator / 2) / denominator;
    }

    /// @dev Calculates compound interest using Taylor series approximation.
    function calculateCompoundInterest(uint256 rate, uint256 periods) internal pure returns (uint256) {
        uint256 linearTerm = rate * periods;
        uint256 quadraticTerm = (linearTerm * linearTerm) / (2 * MATH_PRECISION);
        uint256 cubicTerm = (quadraticTerm * linearTerm) / (3 * MATH_PRECISION);

        uint256 result = linearTerm + quadraticTerm + cubicTerm;

        // Add fourth term when rate * periods exceeds 0.2e18 for improved accuracy
        if (linearTerm > 0.2e18) {
            uint256 quarticTerm = (cubicTerm * linearTerm) / (4 * MATH_PRECISION);

            // Check for overflow before adding the fourth term
            if (result <= type(uint256).max - quarticTerm) {
                result += quarticTerm;
            }
        }

        // Cap the result to prevent downstream uint128 overflows in interest calculations
        // Max safe value is approximately 1e20 to allow for reasonable multiplication with borrower amounts
        uint256 maxSafeResult = 1e20;
        if (result > maxSafeResult) {
            result = maxSafeResult;
        }

        return result;
    }
}
