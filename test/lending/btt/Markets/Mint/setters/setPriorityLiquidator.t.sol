// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetPriorityLiquidator} from "@alto-test/lending/btt/Markets/setters/setPriorityLiquidator.t.sol";

contract SetPriorityLiquidatorTestMint is AltoMarketSetPriorityLiquidator {
    constructor() AltoMarketSetPriorityLiquidator(MarketType.MINT) {}
}
