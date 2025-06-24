// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetBorrowOpeningFee} from "@alto-test/lending/btt/Markets/setters/setBorrowOpeningFee.t.sol";

contract SetBorrowOpeningFeeTestMint is AltoMarketSetBorrowOpeningFee {
    constructor() AltoMarketSetBorrowOpeningFee(MarketType.MINT) {}
}
