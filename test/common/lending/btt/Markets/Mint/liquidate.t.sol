// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBorrowMarketliquidate} from "../liquidate.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract MintTestLiquidate is AltoBorrowMarketliquidate {
    constructor() AltoBorrowMarketliquidate(MarketType.MINT) {}
}
