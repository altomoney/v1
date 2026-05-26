// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {
    AltoMarketSetAuthorizedLiquidationPeriphery
} from "@alto-test/lending/btt/Markets/setters/setAuthorizedLiquidationPeriphery.t.sol";

contract SetAuthorizedLiquidationPeripheryTestMint is AltoMarketSetAuthorizedLiquidationPeriphery {
    constructor() AltoMarketSetAuthorizedLiquidationPeriphery(MarketType.MINT) {}
}
