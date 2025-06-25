// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";

contract TWAlto_activateEmergencySweep is TWAltoBaseTest {
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

    modifier whenAllConditionsAreValid() {
        // All conditions valid by default setup
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_CallerIsNotOwner() public givenCallerIsNotOwner {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        twAlto.activateEmergencySweep();
    }

    function test_Success_WhenAllConditionsAreValid() public givenCallerIsOwner whenAllConditionsAreValid {
        // Verify initial state
        assertEq(twAlto.lastEmergencySweep(), 0);

        // It should emit ActivateEmergencySweep event
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.ActivateEmergencySweep();

        vm.prank(admin);
        twAlto.activateEmergencySweep();

        // It should set lastEmergencySweep to current block timestamp
        assertEq(twAlto.lastEmergencySweep(), block.timestamp);
    }

    function test_ActivateEmergencySweep_UpdatesTimestamp() public givenCallerIsOwner whenAllConditionsAreValid {
        uint256 initialTime = block.timestamp;

        vm.prank(admin);
        twAlto.activateEmergencySweep();

        // Verify timestamp is set correctly
        assertEq(twAlto.lastEmergencySweep(), initialTime);

        // Fast forward time and activate again
        skip(1000);

        vm.prank(admin);
        twAlto.activateEmergencySweep();

        // Should update to new timestamp
        assertEq(twAlto.lastEmergencySweep(), block.timestamp);
        assertEq(twAlto.lastEmergencySweep(), initialTime + 1000);
    }

    function test_ActivateEmergencySweep_CanBeCalledMultipleTimes()
        public
        givenCallerIsOwner
        whenAllConditionsAreValid
    {
        // First activation
        vm.prank(admin);
        twAlto.activateEmergencySweep();
        uint256 firstTimestamp = twAlto.lastEmergencySweep();

        // Skip some time
        skip(100);

        // Second activation should work and update timestamp
        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.ActivateEmergencySweep();

        vm.prank(admin);
        twAlto.activateEmergencySweep();
        uint256 secondTimestamp = twAlto.lastEmergencySweep();

        assertGt(secondTimestamp, firstTimestamp);
        assertEq(secondTimestamp, firstTimestamp + 100);
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_RevertWhen_CallerIsNotOwner(address _caller) public givenCallerIsNotOwner {
        vm.assume(_caller != admin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        vm.prank(_caller);
        twAlto.activateEmergencySweep();
    }

    function testFuzz_ActivateEmergencySweep_AtDifferentTimes(uint256 _timeSkip) public givenCallerIsOwner {
        // Bound to reasonable range
        _timeSkip = bound(_timeSkip, 0, 365 days);

        // Skip to different time
        skip(_timeSkip);
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, false, false, false);
        emit TWAltoEventsLib.ActivateEmergencySweep();

        vm.prank(admin);
        twAlto.activateEmergencySweep();

        assertEq(twAlto.lastEmergencySweep(), expectedTimestamp);
    }
}
