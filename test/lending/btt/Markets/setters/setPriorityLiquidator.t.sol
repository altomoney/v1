// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract AltoMarketSetPriorityLiquidator is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setPriorityLiquidator(address(0), true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address liquidator = address(0x123);
        bool status = true;

        // it should emit PriorityLiquidatorUpdated event
        vm.expectEmit();
        emit IMarketEvents.PriorityLiquidatorUpdated(liquidator, status);

        market.setPriorityLiquidator(liquidator, status);

        // it should update priorityLiquidators mapping
        assertEq(market.priorityLiquidators(liquidator), status);
    }

    function test_RevertWhen_LiquidatorIsZeroAddress() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setPriorityLiquidator(address(0), true);
    }
}
