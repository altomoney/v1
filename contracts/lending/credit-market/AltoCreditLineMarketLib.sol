// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AssetShareConversionMath} from "../libraries/AssetShareConversionMath.sol";
import {Balance, BaseMarketInitParams, Position} from "../interfaces/IMarket.sol";
import {CreditMarketInitParams, IAltoConvexCreditLineMarketErrors} from "../interfaces/IAltoConvexCreditLineMarket.sol";
import {IIrm, IRMType} from "../interfaces/IIrm.sol";

import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

/// @title Alto Credit Line Market Library
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Shared initialization validation, position valuation, and foreclosure accounting for credit-line markets.
/// @dev External functions execute in the calling market context and operate on the supplied market storage.
library AltoCreditLineMarketLib {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    /// @notice Validates the parameters used to initialize a credit-line market.
    /// @dev Reverts for zero required addresses, invalid fee or LTV bounds, a zero credit limit, or a non-fixed IRM.
    /// @param initParams The complete credit-line market initialization parameters.
    function validateInitialization(CreditMarketInitParams memory initParams) external view {
        BaseMarketInitParams memory baseMarketInitParams = initParams.baseMarketInitParams;

        if (initParams.creditAccount == address(0) || baseMarketInitParams.feeRecipient == address(0)) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress();
        }
        if (
            initParams.creditLimit == 0 || initParams.initialBorrowOpeningFee > MATH_PRECISION
                || baseMarketInitParams.maxLtv >= initParams.foreclosureLtv
                || initParams.foreclosureLtv > MATH_PRECISION
                || IIrm(baseMarketInitParams.irm).IRM_TYPE() != IRMType.FIXED_RATE
        ) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput();
        }
    }

    /// @notice Returns whether a position is solvent at the configured maximum LTV.
    /// @dev Debt-free positions skip the oracle lookup. Collateral value is rounded down and debt value is rounded up.
    /// @param userPosition The credit account position to evaluate.
    /// @param totalBorrowed The market total-borrowed accounting used to convert debt shares to assets.
    /// @param oracle The lending oracle used to value the position collateral.
    /// @param maxLtv The maximum permitted loan-to-value ratio, expressed with `MATH_PRECISION`.
    /// @return solvent True when position debt does not exceed the maximum permitted borrow value.
    function isSolvent(Position storage userPosition, Balance storage totalBorrowed, address oracle, uint256 maxLtv)
        external
        view
        returns (bool)
    {
        if (userPosition.borrowShares == 0) {
            return true;
        }

        uint256 collateralValue = _collateralValue(userPosition.collateralAssets, oracle);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(maxLtv);
        return maxBorrowValue >= _borrowValue(userPosition.borrowShares, totalBorrowed);
    }

    /// @notice Validates foreclosure eligibility and clears the foreclosed position and active debt accounting.
    /// @dev Foreclosure requires debt value to strictly exceed the configured foreclosure LTV. Because a credit-line
    ///      market has one credit account, the entire market debt balance is converted to bad debt.
    /// @param userPosition The credit account position to foreclose.
    /// @param totalBorrowed The market total-borrowed accounting to clear.
    /// @param oracle The lending oracle used to value the position collateral.
    /// @param foreclosureLtv The LTV above which the position may be foreclosed, expressed with `MATH_PRECISION`.
    /// @return collateralAmount The collateral assets removed from the position.
    /// @return badDebtAmount The borrowed assets removed from active debt accounting.
    /// @return badDebtShares The borrow shares removed from the position.
    function applyForeclosure(
        Position storage userPosition,
        Balance storage totalBorrowed,
        address oracle,
        uint256 foreclosureLtv
    ) external returns (uint256 collateralAmount, uint256 badDebtAmount, uint128 badDebtShares) {
        if (!isLiquidable(userPosition, totalBorrowed, oracle, foreclosureLtv)) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotForeclosable();
        }

        collateralAmount = userPosition.collateralAssets;
        badDebtShares = userPosition.borrowShares;
        badDebtAmount = totalBorrowed.assets;

        totalBorrowed.assets = 0;
        totalBorrowed.shares = 0;
        userPosition.borrowShares = 0;
        userPosition.collateralAssets = 0;
    }

    /// @notice Returns whether a position is eligible for foreclosure.
    /// @dev Collateral value is rounded down and debt value is rounded up. Equality is not liquidable.
    /// @param userPosition The credit account position to evaluate.
    /// @param totalBorrowed The market total-borrowed accounting used to convert debt shares to assets.
    /// @param oracle The lending oracle used to value the position collateral.
    /// @param foreclosureLtv The foreclosure loan-to-value ratio, expressed with `MATH_PRECISION`.
    /// @return liquidable True when position debt strictly exceeds the foreclosure borrow value.
    function isLiquidable(
        Position storage userPosition,
        Balance storage totalBorrowed,
        address oracle,
        uint256 foreclosureLtv
    ) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(userPosition.collateralAssets, oracle);
        uint256 foreclosureBorrowValue = collateralValue.multiplyWithPrecision(foreclosureLtv);
        return _borrowValue(userPosition.borrowShares, totalBorrowed) > foreclosureBorrowValue;
    }

    /// @notice Converts collateral assets to their value in borrow-token asset units.
    /// @dev Reverts when the oracle price is zero and rounds the resulting collateral value down.
    /// @param collateralAssets The amount of collateral assets to value.
    /// @param oracle The lending oracle that supplies the collateral price.
    /// @return collateralValue The collateral value denominated in borrow-token asset units.
    function _collateralValue(uint128 collateralAssets, address oracle) private view returns (uint256) {
        uint256 collateralPrice = ILendingOracle(oracle).getPrice();
        if (collateralPrice == 0) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidOraclePrice();
        }

        return uint256(collateralAssets).divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
    }

    /// @notice Converts position borrow shares to borrowed assets.
    /// @dev Uses the market total-borrowed ratio and rounds the resulting asset amount up.
    /// @param borrowShares The position borrow shares to convert.
    /// @param totalBorrowed The market total-borrowed assets and shares.
    /// @return borrowValue The borrowed assets represented by `borrowShares`.
    function _borrowValue(uint128 borrowShares, Balance storage totalBorrowed) private view returns (uint256) {
        return uint256(borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
    }
}
