// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract SetPriorityLiquidatorTest is AltoMintMarketTest {
    address internal mockLiquidator = makeAddr("mockLiquidator");

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setPriorityLiquidator(mockLiquidator, true);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_UpdatePriorityLiquidatorStatusWhen_LiquidatorIsZeroAddress() external givenCallerIsOwner {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setPriorityLiquidator(address(0), true);
        vm.stopPrank();
    }

    function test_UpdatePriorityLiquidatorStatusWhen_LiquidatorIsValidAddress() external givenCallerIsOwner {
        // Check initial state
        bool initialStatus = market.priorityLiquidators(mockLiquidator);
        assertFalse(initialStatus);

        vm.startPrank(owner);

        // it should update priority liquidator status
        market.setPriorityLiquidator(mockLiquidator, true);
        bool priorityStatus = market.priorityLiquidators(mockLiquidator);
        assertTrue(priorityStatus);

        // Remove priority liquidator status
        market.setPriorityLiquidator(mockLiquidator, false);
        bool nonPriorityStatus = market.priorityLiquidators(mockLiquidator);
        assertFalse(nonPriorityStatus);

        vm.stopPrank();
    }
}
