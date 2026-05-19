// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidationPeriphery_SetMarketRegistry_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        address newRegistry = address(new MarketRegistry(OWNER));

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.setMarketRegistry(newRegistry);
    }

    function test_RevertWhen_NewMarketRegistryIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        periphery.setMarketRegistry(address(0));
    }

    function test_RevertWhen_NewMarketRegistryIsAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.AlreadySet.selector);
        periphery.setMarketRegistry(address(registry));
    }

    function test_SetMarketRegistry_UpdatesStateAndEmitsEvent() public {
        MarketRegistry newRegistry = new MarketRegistry(OWNER);

        vm.prank(OWNER);
        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.MarketRegistrySet(address(registry), address(newRegistry));
        periphery.setMarketRegistry(address(newRegistry));

        assertEq(address(periphery.marketRegistry()), address(newRegistry));
    }
}
