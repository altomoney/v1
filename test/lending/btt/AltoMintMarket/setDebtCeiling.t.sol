// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SetDebtCeilingTest is AltoMintMarketTest {
    function test_RevertWhen_CallerIsNotOwner() external {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setDebtCeiling(500000 ether);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_NewDebtCeilingIsLessThanCurrentTotalBorrowed() external givenCallerIsOwner {
        // First, simulate some borrowed assets
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Now try to set debt ceiling below borrowed amount
        vm.startPrank(owner);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.setDebtCeiling(50 ether);
        vm.stopPrank();
    }

    function test_UpdateDebtCeilingAndTotalSupplyWhen_NewDebtCeilingIsValid() external givenCallerIsOwner {
        // Test with debt ceiling greater than borrowed amount
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Set debt ceiling greater than borrowed amount
        vm.startPrank(owner);
        uint256 newDebtCeiling = 500000 ether;
        market.setDebtCeiling(newDebtCeiling);

        // it should update debt ceiling and total supply
        (uint128 totalSupplyAssets,) = market.totalSupply();
        assertEq(totalSupplyAssets, newDebtCeiling);
        vm.stopPrank();
    }

    function test_UpdateDebtCeilingAndTotalSupplyWhen_NewDebtCeilingIsValidWithZero() external givenCallerIsOwner {
        // Test with zero debt ceiling when no borrows exist
        vm.startPrank(owner);
        market.setDebtCeiling(0);

        // it should update debt ceiling and total supply
        (uint128 totalSupplyAssets,) = market.totalSupply();
        assertEq(totalSupplyAssets, 0);
        vm.stopPrank();
    }
}
