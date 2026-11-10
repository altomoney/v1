// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoBorrowMarketGovernanceLiquidate} from "../governanceLiquidate.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract MintTestGovernanceLiquidate is AltoBorrowMarketGovernanceLiquidate {
    constructor() AltoBorrowMarketGovernanceLiquidate(MarketType.MINT) {}
}

