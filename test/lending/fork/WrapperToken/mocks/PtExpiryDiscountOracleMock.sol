// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {IPtWithExpiry} from "./IPtWithExpiry.sol";

/// @title PtExpiryDiscountOracleMock
/// @notice Mock lending oracle for PT collateral that linearly discounts price by time to expiry.
/// @dev Price formula:
///      `timeToExpiry = max(0, expiry - block.timestamp)`
///      `discount = DISCOUNT_PER_YEAR * timeToExpiry / SECONDS_PER_YEAR`
///      `ptPrice = decimalScale * (1 - discount)`
///      `price = ptPrice * exchangeRate / 10^exchangeRateDecimals`
///      where `decimalScale = 10^(36 + borrowDecimals - collateralDecimals)`.
contract PtExpiryDiscountOracleMock is ILendingOracle {
    using FixedPointMath for uint256;

    /// @notice Linear discount applied per year of remaining time to expiry (5% = 0.05e18).
    uint256 public constant DISCOUNT_PER_YEAR = 0.05e18;

    /// @notice Seconds in one year used for linear discount accrual.
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice PT token whose `expiry()` drives the discount schedule.
    address public immutable ptToken;

    /// @notice Decimals of the collateral token priced by this oracle.
    uint8 public immutable collateralDecimals;

    /// @notice Decimals of the borrow token used for oracle precision scaling.
    uint8 public immutable borrowDecimals;

    /// @notice Wrapper exchange rate numerator applied on top of the PT price.
    uint256 public immutable exchangeRate;

    /// @notice Decimal scale for `exchangeRate` (price is multiplied by `exchangeRate / 10**exchangeRateDecimals`).
    uint8 public immutable exchangeRateDecimals;

    /// @param ptToken_ PT asset with an `expiry()` timestamp.
    /// @param collateralDecimals_ Decimals of the collateral token (e.g. wrapper token).
    /// @param borrowDecimals_ Decimals of the borrow token (e.g. DUSD).
    /// @param exchangeRate_ Exchange rate applied to the discounted PT price.
    /// @param exchangeRateDecimals_ Decimal scale for `exchangeRate_`.
    constructor(
        address ptToken_,
        uint8 collateralDecimals_,
        uint8 borrowDecimals_,
        uint256 exchangeRate_,
        uint8 exchangeRateDecimals_
    ) {
        ptToken = ptToken_;
        collateralDecimals = collateralDecimals_;
        borrowDecimals = borrowDecimals_;
        exchangeRate = exchangeRate_;
        exchangeRateDecimals = exchangeRateDecimals_;
    }

    /// @inheritdoc ILendingOracle
    function getPrice() external view returns (uint256) {
        uint256 timeToExpiry = _timeToExpiry(IPtWithExpiry(ptToken).expiry());
        uint256 discountWad = _discountWad(timeToExpiry);
        uint256 oneMinusDiscount = MATH_PRECISION - discountWad;

        uint256 ptPrice = _decimalScale().multiplyWithPrecision(oneMinusDiscount);

        return ptPrice * exchangeRate / (10 ** uint256(exchangeRateDecimals));
    }

    /// @notice Returns remaining seconds until PT expiry.
    function timeToExpiry() external view returns (uint256) {
        return _timeToExpiry(IPtWithExpiry(ptToken).expiry());
    }

    /// @notice Returns the current linear discount factor in WAD precision.
    function currentDiscountWad() external view returns (uint256) {
        return _discountWad(_timeToExpiry(IPtWithExpiry(ptToken).expiry()));
    }

    function _timeToExpiry(uint256 expiry) internal view returns (uint256) {
        if (expiry <= block.timestamp) return 0;
        return expiry - block.timestamp;
    }

    function _discountWad(uint256 timeToExpiry) internal pure returns (uint256) {
        if (timeToExpiry == 0) return 0;

        uint256 discountWad = (DISCOUNT_PER_YEAR * timeToExpiry) / SECONDS_PER_YEAR;
        return discountWad > MATH_PRECISION ? MATH_PRECISION : discountWad;
    }

    function _decimalScale() internal view returns (uint256) {
        if (borrowDecimals >= collateralDecimals) {
            return LENDING_ORACLE_PRICE_PRECISION * (10 ** uint256(borrowDecimals - collateralDecimals));
        }

        return LENDING_ORACLE_PRICE_PRECISION / (10 ** uint256(collateralDecimals - borrowDecimals));
    }
}
