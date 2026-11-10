// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoMarketRemoveCollateral} from "../removeCollateral.t.sol";
import {MarketType} from "../MarketCommon.t.sol";

contract RemoveCollateralTestBorrow is AltoMarketRemoveCollateral {
    constructor() AltoMarketRemoveCollateral(MarketType.BORROW) {}
}
