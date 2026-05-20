// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {ILiquidationPeripheryErrors} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_Constructor_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_MarketRegistryIsZeroAddress() public {
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        new LiquidationPeriphery(OWNER, address(0), address(usm));
    }

    function test_RevertWhen_UsmIsZeroAddress() public {
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        new LiquidationPeriphery(OWNER, address(registry), address(0));
    }

    function test_Constructor_SetsState() public view {
        assertEq(address(periphery.marketRegistry()), address(registry));
        assertEq(address(periphery.usm()), address(usm));
        assertEq(periphery.BORROW_TOKEN(), address(borrowToken));
    }
}
