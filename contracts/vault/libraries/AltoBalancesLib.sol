// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Market, MarketLib} from "./MarketLib.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

/// @title AltoBalancesLib
/// @author GPM
/// @author Adapted from Morpho Labs' MorphoBalancesLib (https://github.com/morpho-org/morpho-blue) for Alto borrow markets.
/// @custom:contact security@altofoundation.org
/// @notice Helper library exposing getters with the expected value after interest accrual.
/// @dev The getter to retrieve the expected total borrow shares is not exposed because interest accrual does not apply
/// to it. The value can be queried directly on the market contract using `totalBorrowShares()`.
library AltoBalancesLib {
    using FixedPointMath for uint256;
    using FixedPointMath for uint128;
    using MarketLib for address;
    using AssetShareConversionMath for uint256;
    using AssetShareConversionMath for uint128;
    using Uint128Converter for uint256;

    /// @notice Returns the expected market balances of a market after having accrued interest.
    /// @return The expected total supply assets.
    /// @return The expected total supply shares.
    /// @return The expected total borrow assets.
    /// @return The expected total borrow shares.
    function expectedMarketBalances(address market) internal view returns (uint256, uint256, uint256, uint256) {
        Market memory marketState = market.getState();

        uint256 elapsed = block.timestamp - marketState.lastUpdate;
        address irm = IMarketBase(market).irm();

        // Skipped if elapsed == 0 or totalBorrowAssets == 0 because interest would be null, or if irm == address(0).
        if (elapsed != 0 && marketState.totalBorrowAssets != 0 && irm != address(0)) {
            (uint256 interest,) =
                IIrm(irm).updateInterestRateView(marketState.totalSupplyAssets, marketState.totalBorrowAssets);
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

        return (
            marketState.totalSupplyAssets,
            marketState.totalSupplyShares,
            marketState.totalBorrowAssets,
            marketState.totalBorrowShares
        );
    }
}
