// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketRemoveCollateral} from "../removeCollateral.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract RemoveCollateralTestDaoMint is AltoMarketRemoveCollateral {
    AltoDaoMintMarket public daoMintMarket;

    constructor() AltoMarketRemoveCollateral(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, true);
        daoMintMarket.setAuthorizedController(USER_2, true);
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
        market.removeCollateral(COLLATERAL_INPUT, USER, USER, "");
        vm.stopPrank();
    }

    modifier givenPublicAccessIsEnabled() {
        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(USER, false);
        daoMintMarket.setAuthorizedController(USER_2, false);
        daoMintMarket.setAuthorizedController(address(this), false);
        daoMintMarket.setPublicAccessEnabled(true);
        vm.stopPrank();
        _;
    }

    function test_SucceedWhen_PublicAccessIsEnabled() external givenValidInputs givenPublicAccessIsEnabled {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false);
        emit IMarketEvents.RemoveCollateral(USER, USER, USER, COLLATERAL_INPUT);
        market.removeCollateral(COLLATERAL_INPUT, USER, USER, "");
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        deal(address(collateralToken), OWNER, COLLATERAL_INPUT);
        collateralToken.approve(address(market), COLLATERAL_INPUT);
        market.addCollateral(COLLATERAL_INPUT, OWNER);
        _;
        vm.stopPrank();
    }

    function test_SucceedWhen_CallerIsOwner() external givenValidInputs givenCallerIsOwner {
        vm.expectEmit(true, true, true, false);
        emit IMarketEvents.RemoveCollateral(OWNER, OWNER, OWNER, COLLATERAL_INPUT);
        market.removeCollateral(COLLATERAL_INPUT, OWNER, OWNER, "");
    }
}
