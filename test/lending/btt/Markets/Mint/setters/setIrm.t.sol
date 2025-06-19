// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetIrm} from "@alto-test/lending/btt/Markets/setters/setIrm.t.sol";

contract SetIrmTestMint is AltoMarketSetIrm {
    constructor() AltoMarketSetIrm(MarketType.MINT) {}
}
