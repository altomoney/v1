// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMarketBase, IMarketStaticTypes} from "@alto/lending/interfaces/IMarket.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

/// @dev Warning: `totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
/// @dev Warning: `totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
/// @dev Warning: `totalSupplyShares` does not contain the additional shares accrued by `feeRecipient` since the last
/// interest accrual.
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

/// @title MarketLib
/// @notice Library to fetch market state for Alto markets.
library MarketLib {
    /// @notice Fetches market state from the given market address and returns a Market struct.
    /// @param market The address of the market
    /// @return marketState The Market struct with totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares,
    /// lastUpdate from the market's IRM (by IRM_TYPE), and fee (interestFee for borrow markets, 0 for mint markets).
    function getState(address market) internal view returns (Market memory marketState) {
        (uint128 totalSupplyAssets, uint128 totalSupplyShares) = IMarketStaticTypes(market).totalSupply();
        (uint128 totalBorrowAssets, uint128 totalBorrowShares) = IMarketStaticTypes(market).totalBorrowed();

        uint48 lastUpdate;
        address irm = IMarketBase(market).irm();
        if (irm != address(0)) {
            // This library is used in context of AltoVault to be used for fetching state of Alto borrow markets.
            // Since Alto borrow markets use AdaptiveCurveIrm, we can safely cast to AdaptiveCurveIrm.
            (, lastUpdate) = AdaptiveCurveIrm(irm).irState();
        }

        // This library is used in context of AltoVault to be used for fetching state of Alto borrow markets.
        // Since Alto borrow markets contains interestFee, we can safely cast to AltoBorrowMarket and get the interestFee.
        uint128 fee = uint128(AltoBorrowMarket(market).interestFee());

        marketState = Market({
            totalSupplyAssets: totalSupplyAssets,
            totalSupplyShares: totalSupplyShares,
            totalBorrowAssets: totalBorrowAssets,
            totalBorrowShares: totalBorrowShares,
            lastUpdate: uint128(lastUpdate),
            fee: fee
        });
    }
}
