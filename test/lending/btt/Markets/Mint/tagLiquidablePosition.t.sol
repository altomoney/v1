// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketTagLiquidablePosition} from "../tagLiquidablePosition.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract TagLiquidablePositionTestMint is AltoMarketTagLiquidablePosition {
    constructor() AltoMarketTagLiquidablePosition(MarketType.MINT) {}
}
