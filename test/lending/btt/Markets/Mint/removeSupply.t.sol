// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract AltoMintMarketRemoveSupply is MarketCommon {
    constructor() MarketCommon(MarketType.MINT) {}

    function test_ShouldRevert() external {
        // it should revert
        vm.expectRevert(AltoMintMarket.AltoMintMarketNotImplemented.selector);
        market.removeSupply(100 ether, 0, USER, USER);
    }
}
