// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketEvents, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract AltoMarketSetAuthorizedLiquidationPeriphery is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setAuthorizedLiquidationPeriphery(address(0x123), true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address periphery = address(0x123);
        bool isAuthorized = true;

        // it should emit SetAuthorizedLiquidationPeriphery event
        vm.expectEmit();
        emit IMarketEvents.SetAuthorizedLiquidationPeriphery(periphery, isAuthorized);

        market.setAuthorizedLiquidationPeriphery(periphery, isAuthorized);

        // it should update authorizedLiquidationPeriphery mapping
        assertEq(market.authorizedLiquidationPeriphery(periphery), isAuthorized);
    }

    function test_RevertWhen_PeripheryIsZeroAddress() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setAuthorizedLiquidationPeriphery(address(0), true);
    }
}
