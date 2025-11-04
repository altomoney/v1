// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketTagLiquidablePosition} from "../tagLiquidablePosition.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";

contract TagLiquidablePositionTestDaoMint is AltoMarketTagLiquidablePosition {
    AltoDaoMintMarket public daoMintMarket;

    constructor() AltoMarketTagLiquidablePosition(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setPublicAccessEnabled(true);
        vm.stopPrank();
    }
}
