// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoMarketTagLiquidablePosition} from "../tagLiquidablePosition.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract TagLiquidablePositionTestBorrow is AltoMarketTagLiquidablePosition {
    constructor() AltoMarketTagLiquidablePosition(MarketType.BORROW) {}
}
