// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IMarket, MarketType} from "@alto/lending/interfaces/IMarket.sol";

struct MarketUpgradeBatchReport {
    address[] markets;
    address[] implementations;
}

/// @notice Deploys a new market implementation per market address based on on-chain MARKET_TYPE
contract MarketUpgradeBatch {
    MarketUpgradeBatchReport internal report;

    error UnsupportedMarketType();

    constructor(address[] memory markets) {
        uint256 count = markets.length;
        report.markets = markets;
        report.implementations = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            MarketType marketType = IMarket(markets[i]).MARKET_TYPE();

            if (marketType == MarketType.MINT) {
                report.implementations[i] = address(new AltoMintMarket());
            } else if (marketType == MarketType.BORROW) {
                report.implementations[i] = address(new AltoBorrowMarket());
            } else {
                revert UnsupportedMarketType();
            }
        }
    }

    function getReport() external view returns (MarketUpgradeBatchReport memory) {
        return report;
    }
}
