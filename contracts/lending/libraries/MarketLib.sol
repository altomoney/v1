// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IMarketStaticTypes, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoBorrowMarket} from "@alto/lending/interfaces/IAltoBorrowMarket.sol";

/// @dev Snapshot of market state. Totals do not include interest accrued after `lastUpdate`.
/// @dev Warning: `totalSupplyAssets` and `totalBorrowAssets` do not contain interest since the last accrual.
/// @dev Warning: `totalSupplyShares` does not include shares accrued by the fee recipient since the last accrual.
/// @dev `lastUpdate` is the timestamp of the last IRM update (from the market's IRM, by IRM_TYPE).
/// @dev `fee` is the market's interest fee (from interestFee() for borrow markets, 0 for mint markets).
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 fee;
}

/// @title MarketLib
/// @custom:contact security@altofoundation.org
/// @notice Library to fetch market state for Alto markets.
library MarketLib {
    /// @notice Returns total supply (assets, shares) of the market.
    function totalSupply(address market) internal view returns (uint128 assets, uint128 shares) {
        return IMarketStaticTypes(market).totalSupply();
    }

    /// @notice Returns total borrowed (assets, shares) of the market.
    function totalBorrowed(address market) internal view returns (uint128 assets, uint128 shares) {
        return IMarketStaticTypes(market).totalBorrowed();
    }

    /// @notice Returns the supply shares of `user` in the market.
    function userSupplyShares(address market, address user) internal view returns (uint128) {
        return IMarket(market).position(user).supplyShares;
    }

    /// @notice Returns the borrow shares of `user` in the market.
    function userBorrowShares(address market, address user) internal view returns (uint128) {
        return IMarket(market).position(user).borrowShares;
    }

    /// @notice Returns the collateral assets of `user` in the market.
    function userCollateralAssets(address market, address user) internal view returns (uint128) {
        return IMarket(market).position(user).collateralAssets;
    }

    /// @notice Returns the IRM address of the market.
    function irm(address market) internal view returns (address) {
        return IMarket(market).irm();
    }

    /// @notice Fetches market state from the given market address and returns a Market struct.
    /// @param market The address of the market
    /// @return marketState The Market struct with totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares, and fee.
    function getState(address market) internal view returns (Market memory marketState) {
        (uint128 totalSupplyAssets, uint128 totalSupplyShares) = totalSupply(market);
        (uint128 totalBorrowAssets, uint128 totalBorrowShares) = totalBorrowed(market);

        uint128 fee = uint128(IAltoBorrowMarket(market).interestFee());

        marketState = Market({
            totalSupplyAssets: totalSupplyAssets,
            totalSupplyShares: totalSupplyShares,
            totalBorrowAssets: totalBorrowAssets,
            totalBorrowShares: totalBorrowShares,
            fee: fee
        });
    }
}
