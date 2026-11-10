// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_SetUsmRegistry_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        UsmRegistry newRegistry = new UsmRegistry(OWNER);

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.setUsmRegistry(address(newRegistry));
    }

    function test_RevertWhen_UsmRegistryIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        periphery.setUsmRegistry(address(0));
    }

    function test_SetsUsmRegistryAndEmitsUsmRegistrySet() public {
        UsmRegistry newRegistry = new UsmRegistry(OWNER);
        address oldRegistry = address(periphery.usmRegistry());

        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.UsmRegistrySet(oldRegistry, address(newRegistry));

        vm.prank(OWNER);
        periphery.setUsmRegistry(address(newRegistry));

        assertEq(address(periphery.usmRegistry()), address(newRegistry));
    }
}
