// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerSetEmergencySweepCooldownTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.setEmergencySweepCooldown(1 days);
        vm.stopPrank();
    }

    function test_setEmergencySweepCooldown_validConditions() public {
        uint256 newCooldown = 2 days;

        // Set emergency sweep cooldown
        vm.startPrank(owner);
        tob.setEmergencySweepCooldown(newCooldown);
        vm.stopPrank();

        // Verify cooldown updated
        assertEq(tob._emergencySweepCooldown(), newCooldown, "Emergency sweep cooldown should be updated");
    }
}
