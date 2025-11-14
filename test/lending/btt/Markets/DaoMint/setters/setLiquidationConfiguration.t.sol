// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {
    AltoMarketSetLiquidationConfiguration
} from "@alto-test/lending/btt/Markets/setters/setLiquidationConfiguration.t.sol";

contract SetLiquidationConfigurationTestDaoMint is AltoMarketSetLiquidationConfiguration {
    constructor() AltoMarketSetLiquidationConfiguration(MarketType.DAO_MINT) {}
}
