// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketRepay} from "../repay.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract RepayTestDaoMint is AltoMarketRepay {
    AltoDaoMintMarket public daoMintMarket;

    constructor() AltoMarketRepay(MarketType.DAO_MINT) {}

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

    function test_ShouldRevertWhen_CallerIsNotAuthorized() external givenValidInput givenUserIsNotAuthorized {
        vm.startPrank(USER);

        vm.expectRevert(AltoDaoMintMarket.AltoDaoMintMarketUnauthorized.selector);
        market.repay(REPAY_AMOUNT, 0, USER);
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

    function test_SucceedWhen_PublicAccessIsEnabled() external givenValidInput givenPublicAccessIsEnabled {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false);
        emit IMarketEvents.Repay(USER, USER, REPAY_AMOUNT, 0);
        market.repay(REPAY_AMOUNT, 0, USER);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        deal(address(collateralToken), OWNER, 100 ether);
        deal(address(borrowToken), OWNER, INITIAL_SUPPLY);
        daoMintMarket.setDebtCeiling(INITIAL_SUPPLY);
        collateralToken.approve(address(market), 100 ether);
        borrowToken.approve(address(market), INITIAL_SUPPLY);
        market.addCollateral(10 ether, OWNER);
        market.borrow(5 ether, 0, OWNER, OWNER, "");

        _;

        vm.stopPrank();
    }

    function test_SucceedWhen_CallerIsOwner() external givenCallerIsOwner {
        vm.expectEmit(true, true, true, false);
        emit IMarketEvents.Repay(OWNER, OWNER, 2 ether, 0);
        market.repay(2 ether, 0, OWNER);
    }
}
