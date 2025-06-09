// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SetDebtCeilingTest is AltoMintMarketTest {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert with Ownable: caller is not the owner
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setDebtCeiling(500000 ether);
        vm.stopPrank();
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_NewDebtCeilingIsLessThanTotalBorrowedAssets() external whenCallerIsOwner {
        // First, simulate some borrowed assets
        vm.startPrank(alice);
        market.addCollateral(200 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Now try to set debt ceiling below borrowed amount
        vm.startPrank(owner);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.setDebtCeiling(50 ether);
        vm.stopPrank();
    }

    function test_WhenNewDebtCeilingEqualsTotalBorrowedAssets() external whenCallerIsOwner {
        // First, simulate some borrowed assets
        vm.startPrank(alice);
        market.addCollateral(200 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Set debt ceiling equal to borrowed amount
        uint256 newDebtCeiling = 100 ether;
        market.setDebtCeiling(newDebtCeiling);

        // it should set totalSupply.assets to new debt ceiling
        (uint128 totalSupplyAssets,) = market.totalSupply();
        assertEq(totalSupplyAssets, newDebtCeiling);
    }

    function test_WhenNewDebtCeilingIsGreaterThanTotalBorrowedAssets() external whenCallerIsOwner {
        // First, simulate some borrowed assets
        vm.startPrank(alice);
        market.addCollateral(200 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Set debt ceiling greater than borrowed amount
        uint256 newDebtCeiling = 500000 ether;
        market.setDebtCeiling(newDebtCeiling);

        // it should set totalSupply.assets to new debt ceiling
        (uint128 totalSupplyAssets,) = market.totalSupply();
        assertEq(totalSupplyAssets, newDebtCeiling);
    }

    modifier givenNoOutstandingBorrows() {
        // Ensure no borrows exist (default state)
        _;
    }

    function test_WhenNewDebtCeilingIsZero() external whenCallerIsOwner givenNoOutstandingBorrows {
        // Set debt ceiling to zero
        market.setDebtCeiling(0);

        // it should set totalSupply.assets to zero
        (uint128 totalSupplyAssets,) = market.totalSupply();
        assertEq(totalSupplyAssets, 0);
    }
}
