// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_SetTreasury_Test is LiquidationPeripheryCommon {
    address internal immutable NEW_TREASURY = makeAddr("NewTreasury");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.setTreasury(NEW_TREASURY);
    }

    function test_RevertWhen_TreasuryIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        periphery.setTreasury(address(0));
    }

    function test_SetsTreasuryAndEmitsTreasurySet() public {
        address oldTreasury = periphery.treasury();

        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.TreasurySet(oldTreasury, NEW_TREASURY);

        vm.prank(OWNER);
        periphery.setTreasury(NEW_TREASURY);

        assertEq(periphery.treasury(), NEW_TREASURY);
    }
}
