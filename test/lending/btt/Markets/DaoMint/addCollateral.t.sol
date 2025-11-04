// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketAddCollateral} from "../addCollateral.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract AddCollateralTestDaoMint is AltoMarketAddCollateral {
    AltoDaoMintMarket public daoMintMarket;

    constructor() AltoMarketAddCollateral(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, true);
        daoMintMarket.setAuthorizedController(address(this), true);
        vm.stopPrank();
    }

    modifier givenUserIsNotAuthorized() {
        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, false);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_CallerIsNotAuthorized() external givenValidInputs givenUserIsNotAuthorized {
        vm.startPrank(USER);
        vm.expectRevert(AltoDaoMintMarket.AltoDaoMintMarketUnauthorized.selector);
        market.addCollateral(100 ether, USER);
        vm.stopPrank();
    }

    modifier givenPublicAccessIsEnabled() {
        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, false);
        daoMintMarket.setAuthorizedController(address(this), false);
        daoMintMarket.setPublicAccessEnabled(true);
        vm.stopPrank();
        _;
    }

    function test_SucceedWhen_PublicAccessIsEnabled() external givenValidInputs givenPublicAccessIsEnabled {
        vm.startPrank(USER);
        collateralToken.approve(address(market), 100 ether);
        deal(address(collateralToken), USER, 100 ether);
        vm.expectEmit();
        emit IMarketEvents.AddCollateral(USER, USER, 100 ether);
        market.addCollateral(100 ether, USER);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_SucceedWhen_CallerIsOwner() external givenValidInputs givenCallerIsOwner {
        collateralToken.approve(address(market), 100 ether);
        deal(address(collateralToken), OWNER, 100 ether);
        vm.expectEmit();
        emit IMarketEvents.AddCollateral(OWNER, OWNER, 100 ether);
        market.addCollateral(100 ether, OWNER);
    }
}
