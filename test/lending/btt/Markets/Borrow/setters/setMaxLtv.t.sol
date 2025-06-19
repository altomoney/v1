// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetMaxLtv} from "@alto-test/lending/btt/Markets/setters/setMaxLtv.t.sol";

contract SetMaxLtvTestBorrow is AltoMarketSetMaxLtv {
    constructor() AltoMarketSetMaxLtv(MarketType.BORROW) {}
}
