// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IMarket, MarketType} from "@alto/lending/interfaces/IMarket.sol";

struct MarketUpgradeBatchReport {
    address[] markets;
    address[] implementations;
}

/// @notice Deploys one new implementation per market type and maps each market to the matching implementation.
contract MarketUpgradeBatch {
    MarketUpgradeBatchReport internal report;

    error UnsupportedMarketType();

    constructor(address[] memory markets) {
        uint256 count = markets.length;
        report.markets = markets;
        report.implementations = new address[](count);

        address mintMarketImplementation = address(new AltoMintMarket());
        address borrowMarketImplementation = address(new AltoBorrowMarket());

        for (uint256 i = 0; i < count; i++) {
            MarketType marketType = IMarket(markets[i]).MARKET_TYPE();

            if (marketType == MarketType.MINT) {
                report.implementations[i] = mintMarketImplementation;
            } else if (marketType == MarketType.BORROW) {
                report.implementations[i] = borrowMarketImplementation;
            } else {
                revert UnsupportedMarketType();
            }
        }
    }

    function getReport() external view returns (MarketUpgradeBatchReport memory) {
        return report;
    }
}
