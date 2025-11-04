// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";

contract SetPublicAccessEnabledTestDaoMint is MarketCommon {
    AltoDaoMintMarket public daoMintMarket;

    constructor() MarketCommon(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        daoMintMarket.setPublicAccessEnabled(true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_PublicAccessEnabledIsAlreadyTrue() external whenCallerIsOwner {
        daoMintMarket.setPublicAccessEnabled(true);
        assertTrue(daoMintMarket.publicAccessEnabled());

        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setPublicAccessEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setPublicAccessEnabled(false);
    }

    function test_WhenParameterIsTrue() external whenCallerIsOwner {
        assertFalse(daoMintMarket.publicAccessEnabled());

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetPublicAccessEnabled(true);

        daoMintMarket.setPublicAccessEnabled(true);

        assertTrue(daoMintMarket.publicAccessEnabled());
    }

    function test_WhenParameterIsFalse() external whenCallerIsOwner {
        assertFalse(daoMintMarket.publicAccessEnabled());

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetPublicAccessEnabled(false);

        daoMintMarket.setPublicAccessEnabled(false);

        assertFalse(daoMintMarket.publicAccessEnabled());
    }

    function test_WhenEnablingThenTryingToChange() external whenCallerIsOwner {
        assertFalse(daoMintMarket.publicAccessEnabled());

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.SetPublicAccessEnabled(true);
        daoMintMarket.setPublicAccessEnabled(true);
        assertTrue(daoMintMarket.publicAccessEnabled());

        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setPublicAccessEnabled(false);

        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setPublicAccessEnabled(true);
    }
}
