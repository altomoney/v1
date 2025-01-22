// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerSetEmergencySweepCooldownTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner(address _notOwner, uint256 _newCooldown) public {
        vm.assume(_notOwner != owner);

        vm.startPrank(_notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.setEmergencySweepCooldown(_newCooldown);
        vm.stopPrank();
    }

    function test_setEmergencySweepCooldown_validConditions(uint256 _newCooldown) external {

        // Set emergency sweep cooldown
        vm.startPrank(owner);
        tob.setEmergencySweepCooldown(_newCooldown);
        vm.stopPrank();

        // Verify cooldown updated
        assertEq(tob._emergencySweepCooldown(), _newCooldown, "Emergency sweep cooldown should be updated");
    }
}
