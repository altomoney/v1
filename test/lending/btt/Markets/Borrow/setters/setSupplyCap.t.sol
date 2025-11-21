// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

contract SetSupplyCapTestBorrow is MarketCommon {
    AltoBorrowMarket public borrowMarket;

    constructor() MarketCommon(MarketType.BORROW) {}

    function setUp() public override {
        super.setUp();
        borrowMarket = AltoBorrowMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        borrowMarket.setSupplyCap(1000 ether);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint128 oldSupplyCap = borrowMarket.supplyCap();
        uint128 newSupplyCap = 1000 ether;

        // it should emit SetSupplyCap event
        vm.expectEmit();
        emit AltoBorrowMarket.SetSupplyCap(oldSupplyCap, newSupplyCap);

        borrowMarket.setSupplyCap(newSupplyCap);

        // it should update supplyCap
        assertEq(borrowMarket.supplyCap(), newSupplyCap);
    }
}
