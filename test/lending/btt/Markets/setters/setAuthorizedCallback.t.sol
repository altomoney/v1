// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketEvents, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract AltoMarketSetAuthorizedCallback is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setAuthorizedCallback(address(0), true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address callback = address(0x123);
        bool isAuthorized = true;

        // it should emit SetAuthorizedCallback event
        vm.expectEmit();
        emit IMarketEvents.SetAuthorizedCallback(callback, isAuthorized);

        market.setAuthorizedCallback(callback, isAuthorized);

        // it should update authorizedCallbacks mapping
        assertEq(market.authorizedCallbacks(callback), isAuthorized);
    }

    function test_RevertWhen_CallbackIsZeroAddress() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setAuthorizedCallback(address(0), true);
    }
}
