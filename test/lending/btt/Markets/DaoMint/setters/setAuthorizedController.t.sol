// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";

contract SetAuthorizedControllerTestDaoMint is MarketCommon {
    AltoDaoMintMarket public daoMintMarket;
    address internal controller;

    constructor() MarketCommon(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));
        controller = makeAddr("Controller");
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        daoMintMarket.setAuthorizedController(controller, true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_ControllerIsZeroAddress() external whenCallerIsOwner {
        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setAuthorizedController(address(0), true);
    }

    function test_WhenAuthorizingNewController() external whenCallerIsOwner {
        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetAuthorizedController(controller, true);

        daoMintMarket.setAuthorizedController(controller, true);

        assertTrue(daoMintMarket.authorizedControllers(controller));
    }

    function test_WhenUnauthorizingExistingController() external whenCallerIsOwner {
        daoMintMarket.setAuthorizedController(controller, true);
        assertTrue(daoMintMarket.authorizedControllers(controller));

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetAuthorizedController(controller, false);

        daoMintMarket.setAuthorizedController(controller, false);

        assertFalse(daoMintMarket.authorizedControllers(controller));
    }

    function test_WhenUpdatingControllerStatusMultipleTimes() external whenCallerIsOwner {
        address controller1 = makeAddr("Controller1");
        address controller2 = makeAddr("Controller2");

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetAuthorizedController(controller1, true);
        daoMintMarket.setAuthorizedController(controller1, true);
        assertTrue(daoMintMarket.authorizedControllers(controller1));

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetAuthorizedController(controller2, true);
        daoMintMarket.setAuthorizedController(controller2, true);
        assertTrue(daoMintMarket.authorizedControllers(controller2));
        assertTrue(daoMintMarket.authorizedControllers(controller1));
        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetAuthorizedController(controller1, false);
        daoMintMarket.setAuthorizedController(controller1, false);
        assertFalse(daoMintMarket.authorizedControllers(controller1));
        assertTrue(daoMintMarket.authorizedControllers(controller2));

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetAuthorizedController(controller1, true);
        daoMintMarket.setAuthorizedController(controller1, true);
        assertTrue(daoMintMarket.authorizedControllers(controller1));
        assertTrue(daoMintMarket.authorizedControllers(controller2));

        assertTrue(daoMintMarket.authorizedControllers(controller1));
        assertTrue(daoMintMarket.authorizedControllers(controller2));
    }
}
