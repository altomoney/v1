// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetOracle} from "@alto-test/lending/btt/Markets/setters/setOracle.t.sol";

contract SetOracleTestBorrow is AltoMarketSetOracle {
    constructor() AltoMarketSetOracle(MarketType.BORROW) {}
}
