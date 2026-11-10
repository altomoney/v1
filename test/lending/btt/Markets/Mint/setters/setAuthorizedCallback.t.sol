// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetAuthorizedCallback} from "@alto-test/lending/btt/Markets/setters/setAuthorizedCallback.t.sol";

contract SetAuthorizedCallbackTestMint is AltoMarketSetAuthorizedCallback {
    constructor() AltoMarketSetAuthorizedCallback(MarketType.MINT) {}
}
