// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetLiquidationEngine} from "@alto-test/lending/btt/Markets/setters/setLiquidationEngine.t.sol";

contract SetLiquidationEngineTestMint is AltoMarketSetLiquidationEngine {
    constructor() AltoMarketSetLiquidationEngine(MarketType.MINT) {}
}
