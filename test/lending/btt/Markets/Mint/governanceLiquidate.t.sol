// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBorrowMarketGovernanceLiquidate} from "../governanceLiquidate.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract MintTestGovernanceLiquidate is AltoBorrowMarketGovernanceLiquidate {
    constructor() AltoBorrowMarketGovernanceLiquidate(MarketType.MINT) {}
}

