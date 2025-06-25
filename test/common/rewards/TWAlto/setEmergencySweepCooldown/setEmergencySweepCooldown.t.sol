// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";

contract TWAlto_setEmergencySweepCooldown is TWAltoBaseTest {
    uint256 constant NEW_COOLDOWN = 5 days;
    uint256 constant ZERO_COOLDOWN = 0;

    function setUp() public override {
        super.setUp();
    }

    // ====================================
    //           MODIFIERS
    // ====================================

    modifier givenCallerIsNotOwner() {
        // Will use alice (not owner) in tests
        _;
    }

    modifier givenCallerIsOwner() {
        // Will use admin (owner) in tests
        _;
    }

    modifier whenSettingValidCooldown() {
        // Will be used in tests with valid cooldown values
        _;
    }

    modifier whenSettingZeroCooldown() {
        // Will be used in test with cooldown = 0
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_CallerIsNotOwner() public givenCallerIsNotOwner {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        twAlto.setEmergencySweepCooldown(NEW_COOLDOWN);
    }

    function test_SetValidCooldown() public givenCallerIsOwner whenSettingValidCooldown {
        // Verify initial state (2 days default)
        assertEq(twAlto.emergencySweepCooldown(), 2 days);

        // It should emit SetEmergencySweepCooldown event
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.SetEmergencySweepCooldown(NEW_COOLDOWN);

        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(NEW_COOLDOWN);

        // It should update emergencySweepCooldown to new value
        assertEq(twAlto.emergencySweepCooldown(), NEW_COOLDOWN);
    }

    function test_SetZeroCooldown() public givenCallerIsOwner whenSettingZeroCooldown {
        // It should emit SetEmergencySweepCooldown event with zero
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.SetEmergencySweepCooldown(ZERO_COOLDOWN);

        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(ZERO_COOLDOWN);

        // It should set cooldown to zero
        assertEq(twAlto.emergencySweepCooldown(), ZERO_COOLDOWN);
    }

    function test_SetCooldown_UpdatesMultipleTimes() public givenCallerIsOwner whenSettingValidCooldown {
        uint256 firstCooldown = 1 days;
        uint256 secondCooldown = 10 days;

        // Set first cooldown
        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(firstCooldown);
        assertEq(twAlto.emergencySweepCooldown(), firstCooldown);

        // Set second cooldown
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.SetEmergencySweepCooldown(secondCooldown);

        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(secondCooldown);
        assertEq(twAlto.emergencySweepCooldown(), secondCooldown);
    }

    function test_SetCooldown_LargeCooldownValue() public givenCallerIsOwner whenSettingValidCooldown {
        uint256 largeCooldown = 365 days;

        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.SetEmergencySweepCooldown(largeCooldown);

        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(largeCooldown);

        assertEq(twAlto.emergencySweepCooldown(), largeCooldown);
    }

    function test_SetCooldown_DoesNotAffectLastEmergencySweep() public givenCallerIsOwner whenSettingValidCooldown {
        // Activate emergency sweep first
        vm.prank(admin);
        twAlto.activateEmergencySweep();
        uint256 lastSweepBefore = twAlto.lastEmergencySweep();

        // Change cooldown
        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(NEW_COOLDOWN);

        // lastEmergencySweep should remain unchanged
        assertEq(twAlto.lastEmergencySweep(), lastSweepBefore);
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_RevertWhen_CallerIsNotOwner(address _caller, uint256 _cooldown) public givenCallerIsNotOwner {
        vm.assume(_caller != admin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        vm.prank(_caller);
        twAlto.setEmergencySweepCooldown(_cooldown);
    }

    function testFuzz_SetEmergencySweepCooldown(uint256 _cooldown) public givenCallerIsOwner {
        // Bound to reasonable range (0 to 10 years)
        _cooldown = bound(_cooldown, 0, 10 * 365 days);

        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.SetEmergencySweepCooldown(_cooldown);

        vm.prank(admin);
        twAlto.setEmergencySweepCooldown(_cooldown);

        assertEq(twAlto.emergencySweepCooldown(), _cooldown);
    }
}
