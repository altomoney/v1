// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PausableMock} from "./PausableMock.sol";
import {IPausable} from "../../../../contracts/utils/interfaces/IPausable.sol";

contract WhenNotTest is Test {
    PausableMock internal pausable;
    address internal owner;
    address internal pauser;
    bytes32 internal constant PAUSE_TYPE_ZERO = bytes32(0);
    bytes32 internal constant PAUSE_TYPE_ONE = bytes32(uint256(1));

    function setUp() public {
        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        pausable = new PausableMock(owner);

        // Setup pauser for testing
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);
    }

    /*//////////////////////////////////////////////////////////////
                            REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_PauseTypeIsPaused_Zero() public {
        // Setup: Pause the PAUSE_TYPE_ZERO
        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ZERO, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ZERO));

        // It should revert with IsPaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE_ZERO));
        pausable.testWhenNotModifier(PAUSE_TYPE_ZERO);
    }

    function test_RevertWhen_PauseTypeIsPaused_NonZero() public {
        // Setup: Pause the PAUSE_TYPE_ONE
        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ONE, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ONE));

        // It should revert with IsPaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE_ONE));
        pausable.testWhenNotModifier(PAUSE_TYPE_ONE);
    }

    function testFuzz_RevertWhen_PauseTypeIsPaused(bytes32 pauseType) public {
        // Setup: Set pauser and pause the type
        vm.prank(owner);
        pausable.setPauser(pauser, pauseType, true);
        vm.prank(pauser);
        pausable.pause(pauseType, true);

        // It should revert with IsPaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType));
        pausable.testWhenNotModifier(pauseType);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenNot_PauseTypeIsNotPaused_Zero() public {
        // Ensure PAUSE_TYPE_ZERO is not paused (default state)
        assertFalse(pausable.paused(PAUSE_TYPE_ZERO));

        // It should allow function execution
        bool result = pausable.testWhenNotModifier(PAUSE_TYPE_ZERO);
        assertTrue(result);
    }

    function test_WhenNot_PauseTypeIsNotPaused_NonZero() public {
        // Ensure PAUSE_TYPE_ONE is not paused (default state)
        assertFalse(pausable.paused(PAUSE_TYPE_ONE));

        // It should allow function execution
        bool result = pausable.testWhenNotModifier(PAUSE_TYPE_ONE);
        assertTrue(result);
    }

    function test_WhenNot_PauseTypeHasNeverBeenSet() public {
        // Use a pause type that has never been set
        bytes32 newPauseType = bytes32(uint256(999));

        // It should allow function execution (default false)
        bool result = pausable.testWhenNotModifier(newPauseType);
        assertTrue(result);
    }

    function testFuzz_WhenNot_PauseTypeIsNotPaused(bytes32 pauseType) public {
        // Ensure the pause type is not paused (default or explicitly set to false)
        // Note: We don't set it to true, so it should default to false
        assertFalse(pausable.paused(pauseType));

        // It should allow function execution
        bool result = pausable.testWhenNotModifier(pauseType);
        assertTrue(result);
    }

    /*//////////////////////////////////////////////////////////////
                        STATE TRANSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenNot_PauseTypeUnpausedAfterBeingPaused() public {
        // Setup: Pause then unpause
        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ONE, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ONE));

        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ONE, false);
        assertFalse(pausable.paused(PAUSE_TYPE_ONE));

        // It should allow function execution
        bool result = pausable.testWhenNotModifier(PAUSE_TYPE_ONE);
        assertTrue(result);
    }

    function test_WhenNot_MultiplePauseUnpauseCycle() public {
        bytes32 pauseType = PAUSE_TYPE_ONE;

        // Initial state: not paused
        bool result1 = pausable.testWhenNotModifier(pauseType);
        assertTrue(result1);

        // Pause it
        vm.prank(pauser);
        pausable.pause(pauseType, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType));
        pausable.testWhenNotModifier(pauseType);

        // Unpause it
        vm.prank(pauser);
        pausable.pause(pauseType, false);
        bool result2 = pausable.testWhenNotModifier(pauseType);
        assertTrue(result2);

        // Pause again
        vm.prank(pauser);
        pausable.pause(pauseType, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType));
        pausable.testWhenNotModifier(pauseType);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenNot_MultiplePauseTypesIndependentStates() public {
        bytes32 pauseType1 = bytes32(uint256(1));
        bytes32 pauseType2 = bytes32(uint256(2));
        bytes32 pauseType3 = bytes32(uint256(3));

        // Setup pausers for different types
        vm.startPrank(owner);
        pausable.setPauser(pauser, pauseType1, true);
        pausable.setPauser(pauser, pauseType2, true);
        pausable.setPauser(pauser, pauseType3, true);
        vm.stopPrank();

        // Pause only pauseType1
        vm.prank(pauser);
        pausable.pause(pauseType1, true);

        // pauseType1 should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType1));
        pausable.testWhenNotModifier(pauseType1);

        // pauseType2 and pauseType3 should work
        bool result2 = pausable.testWhenNotModifier(pauseType2);
        bool result3 = pausable.testWhenNotModifier(pauseType3);
        assertTrue(result2);
        assertTrue(result3);
    }

    function test_WhenNot_RealWorldScenario() public {
        // Scenario: Different pause types for different operations
        bytes32 withdrawPause = keccak256("WITHDRAW");
        bytes32 depositPause = keccak256("DEPOSIT");
        bytes32 transferPause = keccak256("TRANSFER");

        // Setup pausers
        vm.startPrank(owner);
        pausable.setPauser(pauser, withdrawPause, true);
        pausable.setPauser(pauser, depositPause, true);
        pausable.setPauser(pauser, transferPause, true);
        vm.stopPrank();

        // Initially all operations should work
        assertTrue(pausable.testWhenNotModifier(withdrawPause));
        assertTrue(pausable.testWhenNotModifier(depositPause));
        assertTrue(pausable.testWhenNotModifier(transferPause));

        // Pause withdrawals during maintenance
        vm.prank(pauser);
        pausable.pause(withdrawPause, true);

        // Withdrawals should be blocked
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, withdrawPause));
        pausable.testWhenNotModifier(withdrawPause);

        // But deposits and transfers should still work
        assertTrue(pausable.testWhenNotModifier(depositPause));
        assertTrue(pausable.testWhenNotModifier(transferPause));

        // Emergency: pause all operations
        vm.startPrank(pauser);
        pausable.pause(depositPause, true);
        pausable.pause(transferPause, true);
        vm.stopPrank();

        // All operations should be blocked
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, withdrawPause));
        pausable.testWhenNotModifier(withdrawPause);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, depositPause));
        pausable.testWhenNotModifier(depositPause);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, transferPause));
        pausable.testWhenNotModifier(transferPause);

        // Resume operations gradually
        vm.startPrank(pauser);
        pausable.pause(depositPause, false);
        pausable.pause(transferPause, false);
        vm.stopPrank();

        // Deposits and transfers should work again
        assertTrue(pausable.testWhenNotModifier(depositPause));
        assertTrue(pausable.testWhenNotModifier(transferPause));

        // But withdrawals still blocked
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, withdrawPause));
        pausable.testWhenNotModifier(withdrawPause);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_WhenNot_RandomPauseTypes(bytes32 pauseType1, bytes32 pauseType2) public {
        vm.assume(pauseType1 != pauseType2);

        // Setup pausers
        vm.startPrank(owner);
        pausable.setPauser(pauser, pauseType1, true);
        pausable.setPauser(pauser, pauseType2, true);
        vm.stopPrank();

        // Both should work initially
        assertTrue(pausable.testWhenNotModifier(pauseType1));
        assertTrue(pausable.testWhenNotModifier(pauseType2));

        // Pause one
        vm.prank(pauser);
        pausable.pause(pauseType1, true);

        // First should revert, second should work
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType1));
        pausable.testWhenNotModifier(pauseType1);

        assertTrue(pausable.testWhenNotModifier(pauseType2));
    }
}
