// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketRemoveCollateral} from "../removeCollateral.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract RemoveCollateralTestBorrow is AltoMarketRemoveCollateral {
    constructor() AltoMarketRemoveCollateral(MarketType.BORROW) {}
}
