// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketAddCollateral} from "../addCollateral.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract AddCollateralTestBorrow is AltoMarketAddCollateral {
    constructor() AltoMarketAddCollateral(MarketType.BORROW) {}
}
