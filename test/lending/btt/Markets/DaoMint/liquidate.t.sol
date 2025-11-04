// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBorrowMarketliquidate} from "../liquidate.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract DaoMintTestLiquidate is AltoBorrowMarketliquidate {
    AltoDaoMintMarket public daoMintMarket;

    constructor() AltoBorrowMarketliquidate(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, true);
        daoMintMarket.setAuthorizedController(address(this), true);
        daoMintMarket.setAuthorizedController(USER_2, true);
        daoMintMarket.setAuthorizedController(LIQUIDATOR, true);
        daoMintMarket.setAuthorizedController(EXTERNAL_LIQUIDATOR, true);
        daoMintMarket.setAuthorizedController(TAGGER, true);
        daoMintMarket.setAuthorizedController(PRIORITY_LIQUIDATOR, true);
        vm.stopPrank();
    }

    modifier givenUserIsNotAuthorized() {
        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER_2, false);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_CallerIsNotAuthorized()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsNotTheTagger
        givenUserIsNotAuthorized
    {
        // Skip combined grace periods
        vm.warp(
            block.timestamp + market.liquidationConfiguration().priorityLiquidationGracePeriod
                + market.liquidationConfiguration().taggerLiquidationGracePeriod + 1
        );

        deal(address(borrowToken), USER_2, 1 ether);
        vm.startPrank(USER_2);
        borrowToken.approve(address(daoMintMarket), 1 ether);

        vm.expectRevert(AltoDaoMintMarket.AltoDaoMintMarketUnauthorized.selector);
        daoMintMarket.liquidate(USER, "");
        vm.stopPrank();
    }

    modifier givenPublicAccessIsEnabled() {
        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, false);
        daoMintMarket.setAuthorizedController(address(this), false);
        daoMintMarket.setAuthorizedController(USER_2, false);
        daoMintMarket.setAuthorizedController(LIQUIDATOR, false);
        daoMintMarket.setAuthorizedController(EXTERNAL_LIQUIDATOR, false);
        daoMintMarket.setAuthorizedController(TAGGER, false);
        daoMintMarket.setAuthorizedController(PRIORITY_LIQUIDATOR, false);
        daoMintMarket.setPublicAccessEnabled(true);
        vm.stopPrank();
        _;
    }

    function test_SucceedWhen_PublicAccessIsEnabled()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsNotTheTagger
        givenPublicAccessIsEnabled
    {
        address randomUser = makeAddr("randomUser");

        // Skip combined grace periods
        vm.warp(
            block.timestamp + market.liquidationConfiguration().priorityLiquidationGracePeriod
                + market.liquidationConfiguration().taggerLiquidationGracePeriod + 1
        );

        deal(address(borrowToken), randomUser, 1 ether);
        vm.startPrank(randomUser);
        borrowToken.approve(address(daoMintMarket), 1 ether);
        vm.expectEmit(true, true, true, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), LIQUIDATOR, 1 ether, 0, 0, 1 ether, 1 ether, 0, 0
        );
        daoMintMarket.liquidate(USER, "");
        vm.stopPrank();
    }

    function test_SucceedWhen_CallerIsOwner()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsNotTheTagger
    {
        // Skip combined grace periods
        vm.warp(
            block.timestamp + market.liquidationConfiguration().priorityLiquidationGracePeriod
                + market.liquidationConfiguration().taggerLiquidationGracePeriod + 1
        );

        deal(address(borrowToken), OWNER, 1 ether);
        vm.startPrank(OWNER);
        borrowToken.approve(address(daoMintMarket), 1 ether);
        vm.expectEmit(true, true, true, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), LIQUIDATOR, 1 ether, 0, 0, 1 ether, 1 ether, 0, 0
        );
        daoMintMarket.liquidate(USER, "");
        vm.stopPrank();
    }
}
