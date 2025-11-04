// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";

contract AddSupplyTestDaoMint is MarketCommon {
    constructor() MarketCommon(MarketType.DAO_MINT) {}

    function test_ShouldRevert() external {
        // it should revert
        vm.expectRevert(AltoDaoMintMarket.AltoDaoMintMarketNotImplemented.selector);
        market.addSupply(100 ether, 0, USER);
    }
}
