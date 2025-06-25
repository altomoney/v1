// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketBorrow} from "../borrow.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract BorrowTestMint is AltoMarketBorrow {
    constructor() AltoMarketBorrow(MarketType.MINT) {}
}
