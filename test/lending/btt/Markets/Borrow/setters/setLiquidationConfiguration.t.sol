// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {
    AltoMarketSetLiquidationConfiguration
} from "@alto-test/lending/btt/Markets/setters/setLiquidationConfiguration.t.sol";

contract SetLiquidationConfigurationTestBorrow is AltoMarketSetLiquidationConfiguration {
    constructor() AltoMarketSetLiquidationConfiguration(MarketType.BORROW) {}
}
