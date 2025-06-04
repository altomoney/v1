// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

uint256 constant MATH_PRECISION = 1e18;

library FixedPointMath {
    using SafeMath for uint256;

    /// @dev Multiplies two numbers and divides by MATH_PRECISION, rounding down.
    function multiplyWithPrecision(uint256 multiplicand, uint256 multiplier) internal pure returns (uint256) {
        return multiplicand.mul(multiplier).div(MATH_PRECISION);
    }

    /// @dev Divides a number by another using MATH_PRECISION, rounding up.
    function divideWithPrecisionUp(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return Math.ceilDiv(numerator.mul(MATH_PRECISION), denominator);
    }

    /// @dev Divides a number by another using MATH_PRECISION, rounding down.
    function divideWithPrecisionDown(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return numerator.mul(MATH_PRECISION).div(denominator);
    }

    /// @dev Performs division with optional rounding up or down.
    function divideWithRounding(uint256 numerator, uint256 multiplier, uint256 denominator, bool roundUp) internal pure returns (uint256) {
        if (roundUp) {
            return Math.ceilDiv(numerator.mul(multiplier), denominator);
        }
        return numerator.mul(multiplier).div(denominator);
    }

    /// @dev Calculates compound interest using Taylor series approximation.
    function calculateCompoundInterest(uint256 rate, uint256 periods) internal pure returns (uint256) {
        uint256 linearTerm = rate.mul(periods);
        uint256 quadraticTerm = linearTerm.mul(linearTerm).div(2 * MATH_PRECISION);
        uint256 cubicTerm = quadraticTerm.mul(linearTerm).div(3 * MATH_PRECISION);

        return linearTerm.add(quadraticTerm).add(cubicTerm);
    }
} 