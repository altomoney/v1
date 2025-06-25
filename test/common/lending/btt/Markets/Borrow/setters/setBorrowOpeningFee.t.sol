// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketType} from "../../MarketCommon.t.sol";
import {AltoMarketSetBorrowOpeningFee} from "@alto-test/common/lending/btt/Markets/setters/setBorrowOpeningFee.t.sol";

contract SetBorrowOpeningFeeTestBorrow is AltoMarketSetBorrowOpeningFee {
    constructor() AltoMarketSetBorrowOpeningFee(MarketType.BORROW) {}
}
