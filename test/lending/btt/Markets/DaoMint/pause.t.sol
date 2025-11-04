// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketPause} from "../pause.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";

contract AltoMarketPauseDaoMint is AltoMarketPause {
    constructor() AltoMarketPause(MarketType.DAO_MINT) {}

    AltoDaoMintMarket public daoMintMarket;

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setPublicAccessEnabled(true);
        vm.stopPrank();
    }
}
