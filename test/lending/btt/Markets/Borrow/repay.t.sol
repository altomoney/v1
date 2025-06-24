// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketRepay} from "../repay.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract RepayTestBorrow is AltoMarketRepay {
    constructor() AltoMarketRepay(MarketType.BORROW) {}
}
