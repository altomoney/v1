// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Market, MarketLib} from "./MarketLib.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {UtilsLib} from "@bundler3/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

/// @title MorphoBalancesLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Helper library exposing getters with the expected value after interest accrual.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
/// @dev The getter to retrieve the expected total borrow shares is not exposed because interest accrual does not apply
/// to it. The value can be queried directly on Morpho using `totalBorrowShares`.
library MorphoBalancesLib {
    using FixedPointMath for uint256;
    using FixedPointMath for uint128;
    using UtilsLib for uint256;
    using MarketLib for address;
    using AssetShareConversionMath for uint256;
    using AssetShareConversionMath for uint128;

    /// @notice Returns the expected market balances of a market after having accrued interest.
    /// @return The expected total supply assets.
    /// @return The expected total supply shares.
    /// @return The expected total borrow assets.
    /// @return The expected total borrow shares.
    function expectedMarketBalances(address market) internal view returns (uint256, uint256, uint256, uint256) {
        Market memory marketState = market.getState();

        address irm = market.irm();

        // Skipped if totalBorrowAssets == 0 because interest would be null, or if irm == address(0).
        if (marketState.totalBorrowAssets != 0 && irm != address(0)) {
            (uint256 interest,) =
                IIrm(irm).updateInterestRateView(marketState.totalSupplyAssets, marketState.totalBorrowAssets);
            if (interest > 0) {
                marketState.totalBorrowAssets += interest.toUint128();
                marketState.totalSupplyAssets += interest.toUint128();

                if (marketState.fee != 0) {
                    uint256 feeAmount = interest.multiplyWithPrecision(marketState.fee);
                    // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                    // that total supply is already updated.
                    uint256 feeShares = feeAmount.convertToSharesDown(
                        marketState.totalSupplyAssets - feeAmount, marketState.totalSupplyShares
                    );
                    marketState.totalSupplyShares += feeShares.toUint128();
                }
            }
        }

        return (
            marketState.totalSupplyAssets,
            marketState.totalSupplyShares,
            marketState.totalBorrowAssets,
            marketState.totalBorrowShares
        );
    }

    /// @notice Returns the expected total supply assets of a market after having accrued interest.
    function expectedTotalSupplyAssets(address market) internal view returns (uint256 totalSupplyAssets) {
        (totalSupplyAssets,,,) = expectedMarketBalances(market);
    }

    /// @notice Returns the expected total borrow assets of a market after having accrued interest.
    function expectedTotalBorrowAssets(address market) internal view returns (uint256 totalBorrowAssets) {
        (,, totalBorrowAssets,) = expectedMarketBalances(market);
    }

    /// @notice Returns the expected total supply shares of a market after having accrued interest.
    function expectedTotalSupplyShares(address market) internal view returns (uint256 totalSupplyShares) {
        (, totalSupplyShares,,) = expectedMarketBalances(market);
    }

    /// @notice Returns the expected supply assets balance of `user` on a market after having accrued interest.
    /// @dev Warning: Wrong for `feeRecipient` because their supply shares increase is not taken into account.
    /// @dev Warning: Withdrawing using the expected supply assets can lead to a revert due to conversion roundings from
    /// assets to shares.
    function expectedSupplyAssets(address market, address user) internal view returns (uint256) {
        uint128 supplyShares = market.userSupplyShares(user);
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = expectedMarketBalances(market);

        return supplyShares.convertToAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    /// @notice Returns the expected borrow assets balance of `user` on a market after having accrued interest.
    /// @dev Warning: The expected balance is rounded up, so it may be greater than the market's expected total borrow
    /// assets.
    function expectedBorrowAssets(address market, address user) internal view returns (uint256) {
        uint128 borrowShares = market.userBorrowShares(user);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = expectedMarketBalances(market);

        return borrowShares.convertToAssetsUp(totalBorrowAssets, totalBorrowShares);
    }
}
