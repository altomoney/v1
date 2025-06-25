// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";

contract TWAlto_setRescueMode is TWAltoBaseTest {
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

    modifier whenSettingRescueModeToTrue() {
        // Will be used in test with _rescueMode = true
        _;
    }

    modifier whenSettingRescueModeToFalse() {
        // Will be used in test with _rescueMode = false
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_CallerIsNotOwner() public givenCallerIsNotOwner {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        twAlto.setRescueMode(true);
    }

    function test_SetRescueModeToTrue() public givenCallerIsOwner whenSettingRescueModeToTrue {
        // Verify initial state
        assertFalse(twAlto.rescueMode());

        // It should emit RescueMode event with true
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.RescueMode(true);

        vm.prank(admin);
        twAlto.setRescueMode(true);

        // It should set rescueMode to true
        assertTrue(twAlto.rescueMode());
    }

    function test_SetRescueModeToFalse() public givenCallerIsOwner whenSettingRescueModeToFalse {
        // Setup: Set rescue mode to true first
        vm.prank(admin);
        twAlto.setRescueMode(true);
        assertTrue(twAlto.rescueMode());

        // It should emit RescueMode event with false
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.RescueMode(false);

        vm.prank(admin);
        twAlto.setRescueMode(false);

        // It should set rescueMode to false
        assertFalse(twAlto.rescueMode());
    }

    function test_SetRescueMode_ToggleMultipleTimes() public givenCallerIsOwner {
        // Start false
        assertFalse(twAlto.rescueMode());

        // Set to true
        vm.prank(admin);
        twAlto.setRescueMode(true);
        assertTrue(twAlto.rescueMode());

        // Set back to false
        vm.prank(admin);
        twAlto.setRescueMode(false);
        assertFalse(twAlto.rescueMode());

        // Set to true again
        vm.prank(admin);
        twAlto.setRescueMode(true);
        assertTrue(twAlto.rescueMode());
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_SetRescueMode(bool _rescueMode) public givenCallerIsOwner {
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.RescueMode(_rescueMode);

        vm.prank(admin);
        twAlto.setRescueMode(_rescueMode);

        assertEq(twAlto.rescueMode(), _rescueMode);
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address _caller, bool _rescueMode) public givenCallerIsNotOwner {
        // Ensure caller is not the owner
        vm.assume(_caller != admin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        vm.prank(_caller);
        twAlto.setRescueMode(_rescueMode);
    }
}
