// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {
    AltoMarketSetAuthorizedLiquidationPeriphery
} from "@alto-test/lending/btt/Markets/setters/setAuthorizedLiquidationPeriphery.t.sol";

contract SetAuthorizedLiquidationPeripheryTestBorrow is AltoMarketSetAuthorizedLiquidationPeriphery {
    constructor() AltoMarketSetAuthorizedLiquidationPeriphery(MarketType.BORROW) {}
}
