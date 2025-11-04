// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetAuthorizedCallback} from "@alto-test/lending/btt/Markets/setters/setAuthorizedCallback.t.sol";

contract SetAuthorizedCallbackTestDaoMint is AltoMarketSetAuthorizedCallback {
    constructor() AltoMarketSetAuthorizedCallback(MarketType.DAO_MINT) {}
}
