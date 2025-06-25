// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PausableMock} from "./PausableMock.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract OnlyPauserTest is Test {
    PausableMock internal pausable;
    address internal owner;
    address internal pauser;
    address internal nonPauser;
    bytes32 internal constant PAUSE_TYPE_ZERO = bytes32(0);
    bytes32 internal constant PAUSE_TYPE_ONE = bytes32(uint256(1));
    bytes32 internal constant PAUSE_TYPE_TWO = bytes32(uint256(2));

    function setUp() public {
        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        nonPauser = makeAddr("nonPauser");
        pausable = new PausableMock(owner);
    }

    /*//////////////////////////////////////////////////////////////
                            REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_CallerIsNotSetAsPauserForPauseTypeZero() public {
        // It should revert with Unauthorized
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, nonPauser, PAUSE_TYPE_ZERO));
        pausable.testOnlyPauserModifier(PAUSE_TYPE_ZERO);
    }

    function test_RevertWhen_CallerIsNotSetAsPauserForPauseTypeNonZero() public {
        // It should revert with Unauthorized
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, nonPauser, PAUSE_TYPE_ONE));
        pausable.testOnlyPauserModifier(PAUSE_TYPE_ONE);
    }

    function test_RevertWhen_CallerIsPauserForDifferentPauseType() public {
        // Setup: Set pauser for PAUSE_TYPE_ONE
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        // It should revert with Unauthorized when accessing PAUSE_TYPE_TWO
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, pauser, PAUSE_TYPE_TWO));
        pausable.testOnlyPauserModifier(PAUSE_TYPE_TWO);
    }

    function testFuzz_RevertWhen_CallerIsNotSetAsPauser(address caller, bytes32 pauseType) public {
        vm.assume(caller != owner);

        // It should revert with Unauthorized
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, caller, pauseType));
        pausable.testOnlyPauserModifier(pauseType);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OnlyPauser_WhenCallerIsSetAsPauserForPauseTypeZero() public {
        // Setup: Set pauser for PAUSE_TYPE_ZERO
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);

        // It should allow function execution
        vm.prank(pauser);
        bool result = pausable.testOnlyPauserModifier(PAUSE_TYPE_ZERO);
        assertTrue(result);
    }

    function test_OnlyPauser_WhenCallerIsSetAsPauserForPauseTypeNonZero() public {
        // Setup: Set pauser for PAUSE_TYPE_ONE
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        // It should allow function execution
        vm.prank(pauser);
        bool result = pausable.testOnlyPauserModifier(PAUSE_TYPE_ONE);
        assertTrue(result);
    }

    function testFuzz_OnlyPauser_WhenCallerIsSetAsPauser(bytes32 pauseType) public {
        // Setup: Set pauser for the pause type
        vm.prank(owner);
        pausable.setPauser(pauser, pauseType, true);

        // It should allow function execution
        vm.prank(pauser);
        bool result = pausable.testOnlyPauserModifier(pauseType);
        assertTrue(result);
    }

    /*//////////////////////////////////////////////////////////////
                        BOUNDARY AND EDGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OnlyPauser_WhenPauserRemovedAfterBeingSet() public {
        // Setup: Set pauser first
        vm.startPrank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);
        // Then remove pauser
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, false);
        vm.stopPrank();

        // It should revert with Unauthorized
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, pauser, PAUSE_TYPE_ONE));
        pausable.testOnlyPauserModifier(PAUSE_TYPE_ONE);
    }

    function test_OnlyPauser_MultiplePausersForSameType() public {
        address pauser1 = makeAddr("pauser1");
        address pauser2 = makeAddr("pauser2");

        // Setup: Set multiple pausers for same type
        vm.startPrank(owner);
        pausable.setPauser(pauser1, PAUSE_TYPE_ONE, true);
        pausable.setPauser(pauser2, PAUSE_TYPE_ONE, true);
        vm.stopPrank();

        // Both pausers should be able to access
        vm.prank(pauser1);
        bool result1 = pausable.testOnlyPauserModifier(PAUSE_TYPE_ONE);
        assertTrue(result1);

        vm.prank(pauser2);
        bool result2 = pausable.testOnlyPauserModifier(PAUSE_TYPE_ONE);
        assertTrue(result2);
    }

    function test_OnlyPauser_SamePauserMultipleTypes() public {
        bytes32 pauseType1 = bytes32(uint256(1));
        bytes32 pauseType2 = bytes32(uint256(2));

        // Setup: Set same pauser for multiple types
        vm.startPrank(owner);
        pausable.setPauser(pauser, pauseType1, true);
        pausable.setPauser(pauser, pauseType2, true);
        vm.stopPrank();

        // Pauser should be able to access both types
        vm.startPrank(pauser);
        bool result1 = pausable.testOnlyPauserModifier(pauseType1);
        bool result2 = pausable.testOnlyPauserModifier(pauseType2);
        vm.stopPrank();

        assertTrue(result1);
        assertTrue(result2);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OnlyPauser_RealWorldScenario() public {
        // Scenario: Different pausers for different operations
        address emergencyPauser = makeAddr("emergencyPauser");
        address routinePauser = makeAddr("routinePauser");
        bytes32 emergencyPause = keccak256("EMERGENCY");
        bytes32 routinePause = keccak256("ROUTINE");

        // Setup different pausers for different scenarios
        vm.startPrank(owner);
        pausable.setPauser(emergencyPauser, emergencyPause, true);
        pausable.setPauser(routinePauser, routinePause, true);
        vm.stopPrank();

        // Emergency pauser can only access emergency functions
        vm.prank(emergencyPauser);
        bool emergency = pausable.testOnlyPauserModifier(emergencyPause);
        assertTrue(emergency);

        // Emergency pauser cannot access routine functions
        vm.prank(emergencyPauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, emergencyPauser, routinePause));
        pausable.testOnlyPauserModifier(routinePause);

        // Routine pauser can only access routine functions
        vm.prank(routinePauser);
        bool routine = pausable.testOnlyPauserModifier(routinePause);
        assertTrue(routine);

        // Routine pauser cannot access emergency functions
        vm.prank(routinePauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, routinePauser, emergencyPause));
        pausable.testOnlyPauserModifier(emergencyPause);
    }
}
