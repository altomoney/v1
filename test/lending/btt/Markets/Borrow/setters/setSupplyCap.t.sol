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
        uint128 oldSupplyCapAssets = borrowMarket.supplyCapAssets();
        uint128 newSupplyCapAssets = 1000 ether;

        // it should emit SetSupplyCap event
        vm.expectEmit();
        emit AltoBorrowMarket.SetSupplyCap(oldSupplyCapAssets, newSupplyCapAssets);

        borrowMarket.setSupplyCap(newSupplyCapAssets);

        // it should update supplyCap
        assertEq(borrowMarket.supplyCapAssets(), newSupplyCapAssets);
    }

    function test_WhenSupplyCapIsZero_ItShouldDisregardCap() external whenCallerIsOwner {
        // Set supply cap to 0 to disable it
        borrowMarket.setSupplyCap(0);
        assertEq(borrowMarket.supplyCapAssets(), 0);

        // Supply a large amount that would exceed a typical cap
        uint256 largeSupplyAmount = type(uint64).max;
        deal(address(borrowToken), SUPPLIER, largeSupplyAmount);

        vm.startPrank(SUPPLIER);
        borrowToken.approve(address(market), largeSupplyAmount);
        // it should succeed without reverting
        market.addSupply(largeSupplyAmount, 0, SUPPLIER);
        vm.stopPrank();

        // Verify total supply exceeds what would have been a typical cap
        assertEq(market.totalSupply().assets, largeSupplyAmount);
    }
}
