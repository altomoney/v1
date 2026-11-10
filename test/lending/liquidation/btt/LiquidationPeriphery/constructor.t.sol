// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_Constructor_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_BorrowTokenIsZeroAddress() public {
        UsmRegistry registry = new UsmRegistry(OWNER);

        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        new LiquidationPeriphery(OWNER, address(0), address(registry), TREASURY);
    }

    function test_RevertWhen_UsmRegistryIsZeroAddress() public {
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        new LiquidationPeriphery(OWNER, address(borrowToken), address(0), TREASURY);
    }

    function test_RevertWhen_TreasuryIsZeroAddress() public {
        UsmRegistry registry = new UsmRegistry(OWNER);

        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        new LiquidationPeriphery(OWNER, address(borrowToken), address(registry), address(0));
    }

    function test_Constructor_SetsOwnerBorrowTokenUsmRegistryTreasuryAndEmitsEvents() public {
        UsmRegistry registry = new UsmRegistry(OWNER);

        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.UsmRegistrySet(address(0), address(registry));

        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.TreasurySet(address(0), TREASURY);

        LiquidationPeriphery deployed =
            new LiquidationPeriphery(OWNER, address(borrowToken), address(registry), TREASURY);

        assertEq(deployed.owner(), OWNER);
        assertEq(deployed.BORROW_TOKEN(), address(borrowToken));
        assertEq(address(deployed.usmRegistry()), address(registry));
        assertEq(deployed.treasury(), TREASURY);
    }
}
