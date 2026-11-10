// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoMarketPause} from "../pause.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract AltoMarketPauseBorrow is AltoMarketPause {
    constructor() AltoMarketPause(MarketType.BORROW) {}
}
