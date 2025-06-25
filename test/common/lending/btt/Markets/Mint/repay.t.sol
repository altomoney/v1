// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketRepay} from "../repay.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract RepayTestMint is AltoMarketRepay {
    constructor() AltoMarketRepay(MarketType.MINT) {}
}
