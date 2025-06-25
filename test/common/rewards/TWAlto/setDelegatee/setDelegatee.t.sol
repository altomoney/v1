// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";
import {Participation} from "@alto/rewards/interfaces/ITWAlto.sol";

contract TWAlto_setDelegatee is TWAltoBaseTest {
    uint8 constant BUCKET_ID = 0;
    address constant DELEGATEE = address(0x123);

    function setUp() public override {
        super.setUp();
    }

    // ====================================
    //           MODIFIERS
    // ====================================

    modifier whenAllConditionsAreValid() {
        // All conditions valid by default setup
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_SetDelegatee_Success() public whenAllConditionsAreValid {
        // It should emit NewDelegate event
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.NewDelegate(alice, BUCKET_ID, DELEGATEE);

        vm.prank(alice);
        twAlto.setDelegatee(BUCKET_ID, DELEGATEE);

        // It should set delegatee for caller's participation in bucket
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position.delegatee, DELEGATEE);
    }

    function test_SetDelegatee_OverwriteExisting() public whenAllConditionsAreValid {
        address firstDelegatee = address(0x456);
        address secondDelegatee = address(0x789);

        // Set first delegatee
        vm.prank(alice);
        twAlto.setDelegatee(BUCKET_ID, firstDelegatee);

        // Verify first delegatee is set
        Participation memory position1 = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position1.delegatee, firstDelegatee);

        // Set second delegatee (overwrite)
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.NewDelegate(alice, BUCKET_ID, secondDelegatee);

        vm.prank(alice);
        twAlto.setDelegatee(BUCKET_ID, secondDelegatee);

        // Verify second delegatee overwrote the first
        Participation memory position2 = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position2.delegatee, secondDelegatee);
    }

    function test_SetDelegatee_ZeroAddress() public whenAllConditionsAreValid {
        // Should allow setting zero address (removing delegation)
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.NewDelegate(alice, BUCKET_ID, address(0));

        vm.prank(alice);
        twAlto.setDelegatee(BUCKET_ID, address(0));

        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position.delegatee, address(0));
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_SetDelegatee(address _delegatee, uint256 _bucketId) public whenAllConditionsAreValid {
        // Bound bucket ID to valid range
        _bucketId = bound(_bucketId, 0, 0); // Only one bucket in test setup

        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.NewDelegate(alice, _bucketId, _delegatee);

        vm.prank(alice);
        twAlto.setDelegatee(_bucketId, _delegatee);

        Participation memory position = twAlto.getParticipation(alice, _bucketId);
        assertEq(position.delegatee, _delegatee);
    }
}
