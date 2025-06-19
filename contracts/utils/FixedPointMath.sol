// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

uint256 constant MATH_PRECISION = 1e18;

/// @title FixedPointMath
/// @author Alto Foundation
/// @custom:contact security@alto.xyz
/// @notice Library for fixed point arithmetic.
library FixedPointMath {
    /// @dev Multiplies two numbers and divides by MATH_PRECISION, rounding down.
    function multiplyWithPrecision(uint256 multiplicand, uint256 multiplier) internal pure returns (uint256) {
        return (multiplicand * multiplier) / MATH_PRECISION;
    }

    /// @dev Divides a number by another using MATH_PRECISION, rounding up.
    function divideWithPrecisionUp(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return Math.ceilDiv(numerator * MATH_PRECISION, denominator);
    }

    /// @dev Divides a number by another using MATH_PRECISION, rounding down.
    function divideWithPrecisionDown(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return (numerator * MATH_PRECISION) / denominator;
    }

    /// @dev Performs division with optional rounding up or down.
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

    /// @dev Calculates compound interest using Taylor series approximation.
    function calculateCompoundInterest(uint256 rate, uint256 periods) internal pure returns (uint256) {
        uint256 linearTerm = rate * periods;
        uint256 quadraticTerm = (linearTerm * linearTerm) / (2 * MATH_PRECISION);
        uint256 cubicTerm = (quadraticTerm * linearTerm) / (3 * MATH_PRECISION);

        return linearTerm + quadraticTerm + cubicTerm;
    }
}
