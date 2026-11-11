// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import {LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {FullMath} from "@alto/oracles/modules/ModuleUniswap/FullMath.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

interface IPTToken {
    function expiry() external view returns (uint256);
}

uint256 constant SECONDS_PER_YEAR = 365.2425 days;

/// @title ModuleLinearDiscount
/// @custom:contact security@altofoundation.org
/// @notice Utility contract to price PT (Principal Token) positions using a linear discount model
/// @dev The discounted price of a PT is: quoteAmount * (1 - timeLeft * baseDiscountPerYear / SECONDS_PER_YEAR)
/// @dev If the PT has matured (block.timestamp >= maturity), the full quoteAmount is returned (discount = 0).
/// @dev Reverts at read time if the computed discount exceeds 1e18 (i.e. the configured discount rate would
/// imply a negative price), which happens when timeLeft * baseDiscountPerYear > SECONDS_PER_YEAR * 1e18.
/// @dev quoteAmount should be the yield-bearing asset in terms of it's underlying asset
/// (ex: for PT-aDAI and if 1 aDAI = 1.05 DAI, quoteAmount should be 1.05 * 10**18).
/// To get price of PT-aDAI, we apply linear discount to that price based on time to maturity because at maturity, the 1 PT-aDAI will be worth to 1 aDAI.
/// @custom:audit Pending
contract ModuleLinearDiscount is FullMath {
    error ModuleLinearDiscountInvalidRate();
    error ModuleLinearDiscountInvalidInput();

    /// @notice Applies a linear time-based discount to quoteAmount and scales to outDecimals
    /// @param quoteAmount The input amount expressed in inDecimals precision
    /// @param config Linear discount node configuration
    /// @return The discounted value of quoteAmount expressed in outDecimals precision
    /// @dev Formula: quoteAmount * (MATH_PRECISION - discount) * 10^outDecimals / (MATH_PRECISION * 10^inDecimals)
    /// @dev Using _mulDiv for 512-bit intermediate precision to prevent phantom overflow
    function readLinearDiscount(uint256 quoteAmount, LinearDiscountNode memory config) public view returns (uint256) {
        uint256 timeLeft = config.maturity > block.timestamp ? config.maturity - block.timestamp : 0;
        uint256 discount = timeLeft * config.baseDiscountPerYear / SECONDS_PER_YEAR;

        if (discount > MATH_PRECISION) revert ModuleLinearDiscountInvalidRate();

        uint256 discountFactor = MATH_PRECISION - discount;
        uint256 powIn = 10 ** config.inDecimals;

        // quoteAmount = quoteAmount * discountFactor * 10^outDecimals / (MATH_PRECISION * 10^inDecimals)
        // Keep a single rounding step for outDecimals < 18 to avoid truncating small non-zero values to zero.
        if (config.outDecimals >= 18) {
            return _mulDiv(quoteAmount, discountFactor * (10 ** (config.outDecimals - 18)), powIn);
        }

        return _mulDiv(quoteAmount, discountFactor, powIn * (10 ** (18 - config.outDecimals)));
    }

    /// @notice Validates the parameters for the linear discount node during initialization or updates
    /// @param config Linear discount node configuration
    /// @dev Reverts if maturity is not in the future, discount rate exceeds 100%/year,
    /// the linear model is infeasible for the given (timeLeft, rate) pair,
    /// or combined decimals exceed the safe overflow bound
    function _validateLinearDiscountParams(LinearDiscountNode memory config) internal view {
        if (config.maturity <= block.timestamp) revert ModuleLinearDiscountInvalidInput();
        if (config.ptToken == address(0)) revert ModuleLinearDiscountInvalidInput();
        if (IPTToken(config.ptToken).expiry() != config.maturity) revert ModuleLinearDiscountInvalidInput();
        if (config.baseDiscountPerYear > MATH_PRECISION) revert ModuleLinearDiscountInvalidInput();

        // The linear model is only well-posed while discount <= 1e18, i.e.
        // timeLeft * baseDiscountPerYear <= SECONDS_PER_YEAR * MATH_PRECISION.
        // Enforcing this at config time prevents misconfigurations that would later
        // brick readLinearDiscount via ModuleLinearDiscountInvalidRate.
        if ((config.maturity - block.timestamp) * config.baseDiscountPerYear > SECONDS_PER_YEAR * MATH_PRECISION) {
            revert ModuleLinearDiscountInvalidInput();
        }

        // 54 comes from LENDING_ORACLE_PRICE_PRECISION (36) plus max token decimals (18);
        // decimal sums above this are unsupported and potentially dangerous.
        if (config.inDecimals + config.outDecimals > 54) revert ModuleLinearDiscountInvalidInput();
    }
}
