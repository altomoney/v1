// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PausableMock} from "./PausableMock.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract PauseTest is Test {
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

    function test_RevertWhen_CallerIsNotPauserForPauseType() public {
        // It should revert with Unauthorized
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, nonPauser, PAUSE_TYPE_ONE));
        pausable.pause(PAUSE_TYPE_ONE, true);
    }

    function testFuzz_RevertWhen_CallerIsNotPauserForPauseType(address caller, bytes32 pauseType, bool _paused)
        public
    {
        vm.assume(caller != owner); // Owner is not automatically a pauser

        // It should revert with Unauthorized
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, caller, pauseType));
        pausable.pause(pauseType, _paused);
    }

    function test_RevertWhen_CallerIsPauserForDifferentPauseType() public {
        // Setup: Set pauser for PAUSE_TYPE_ONE
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        // It should revert with Unauthorized when trying to pause PAUSE_TYPE_TWO
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, pauser, PAUSE_TYPE_TWO));
        pausable.pause(PAUSE_TYPE_TWO, true);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_WhenPauseTypeIsZero_PausedFalse_AlreadyFalse() public {
        // Setup: Set pauser for PAUSE_TYPE_ZERO
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);

        // It it should revert
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE_ZERO, false, false));
        pausable.pause(PAUSE_TYPE_ZERO, false);
    }

    function test_Pause_WhenPauseTypeIsZero_PausedFalse_CurrentlyTrue() public {
        // Setup: Set pauser and pause it first
        vm.startPrank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);
        vm.stopPrank();

        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ZERO, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ZERO));

        // It should set paused to false and emit event
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSE_TYPE_ZERO, false);
        pausable.pause(PAUSE_TYPE_ZERO, false);

        assertFalse(pausable.paused(PAUSE_TYPE_ZERO));
    }

    function test_Pause_WhenPauseTypeIsZero_PausedTrue_AlreadyTrue() public {
        // Setup: Set pauser and pause it first
        vm.startPrank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);
        vm.stopPrank();

        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ZERO, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ZERO));

        // It should set paused to true and emit event (even if already true)
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE_ZERO, true, true));
        pausable.pause(PAUSE_TYPE_ZERO, true);

        assertTrue(pausable.paused(PAUSE_TYPE_ZERO));
    }

    function test_Pause_WhenPauseTypeIsZero_PausedTrue_CurrentlyFalse() public {
        // Setup: Set pauser for PAUSE_TYPE_ZERO
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);

        // It should set paused to true and emit event
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSE_TYPE_ZERO, true);
        pausable.pause(PAUSE_TYPE_ZERO, true);

        assertTrue(pausable.paused(PAUSE_TYPE_ZERO));
    }

    function test_Pause_WhenPauseTypeIsNonZero_PausedFalse_AlreadyFalse() public {
        // Setup: Set pauser for PAUSE_TYPE_ONE
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        // It it should revert
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE_ONE, false, false));
        pausable.pause(PAUSE_TYPE_ONE, false);
    }

    function test_Pause_WhenPauseTypeIsNonZero_PausedFalse_CurrentlyTrue() public {
        // Setup: Set pauser and pause it first
        vm.startPrank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);
        vm.stopPrank();

        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ONE, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ONE));

        // It should set paused to false and emit event
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSE_TYPE_ONE, false);
        pausable.pause(PAUSE_TYPE_ONE, false);

        assertFalse(pausable.paused(PAUSE_TYPE_ONE));
    }

    function test_Pause_WhenPauseTypeIsNonZero_PausedTrue_AlreadyTrue() public {
        // Setup: Set pauser and pause it first
        vm.startPrank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);
        vm.stopPrank();

        vm.prank(pauser);
        pausable.pause(PAUSE_TYPE_ONE, true);
        assertTrue(pausable.paused(PAUSE_TYPE_ONE));

        // It it should revert
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE_ONE, true, true));
        pausable.pause(PAUSE_TYPE_ONE, true);
    }

    function test_Pause_WhenPauseTypeIsNonZero_PausedTrue_CurrentlyFalse() public {
        // Setup: Set pauser for PAUSE_TYPE_ONE
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        // It should set paused to true and emit event
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSE_TYPE_ONE, true);
        pausable.pause(PAUSE_TYPE_ONE, true);

        assertTrue(pausable.paused(PAUSE_TYPE_ONE));
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Pause_Success(bytes32 pauseType, bool _paused) public {
        // Setup: Set pauser for the pause type
        vm.prank(owner);
        pausable.setPauser(pauser, pauseType, true);

        // It should set paused state and emit event
        vm.startPrank(pauser);
        if (_paused == pausable.paused(pauseType)) {
            vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, pauseType, _paused, _paused));
            pausable.pause(pauseType, _paused);
        } else {
            vm.expectEmit();
            emit IPausable.Paused(pauser, pauseType, _paused);
            pausable.pause(pauseType, _paused);
            assertEq(pausable.paused(pauseType), _paused);
        }
        vm.stopPrank();
    }

    function testFuzz_Pause_TogglePause(bytes32 pauseType) public {
        // Setup: Set pauser for the pause type
        vm.prank(owner);
        pausable.setPauser(pauser, pauseType, true);

        vm.startPrank(pauser);

        // Pause it
        pausable.pause(pauseType, true);
        assertTrue(pausable.paused(pauseType));

        // Unpause it
        pausable.pause(pauseType, false);
        assertFalse(pausable.paused(pauseType));

        // Pause it again
        pausable.pause(pauseType, true);
        assertTrue(pausable.paused(pauseType));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_MultipleTypesAndPausers() public {
        address pauser1 = makeAddr("pauser1");
        address pauser2 = makeAddr("pauser2");
        bytes32 pauseType1 = bytes32(uint256(1));
        bytes32 pauseType2 = bytes32(uint256(2));

        // Setup: Set different pausers for different types
        vm.startPrank(owner);
        pausable.setPauser(pauser1, pauseType1, true);
        pausable.setPauser(pauser2, pauseType2, true);
        vm.stopPrank();

        // Pause different types with different pausers
        vm.prank(pauser1);
        pausable.pause(pauseType1, true);

        vm.prank(pauser2);
        pausable.pause(pauseType2, true);

        // Verify states
        assertTrue(pausable.paused(pauseType1));
        assertTrue(pausable.paused(pauseType2));
    }

    function test_Pause_SamePauserMultipleTypes() public {
        bytes32 pauseType1 = bytes32(uint256(1));
        bytes32 pauseType2 = bytes32(uint256(2));

        // Setup: Set same pauser for multiple types
        vm.startPrank(owner);
        pausable.setPauser(pauser, pauseType1, true);
        pausable.setPauser(pauser, pauseType2, true);
        vm.stopPrank();

        // Pause both types
        vm.startPrank(pauser);
        pausable.pause(pauseType1, true);
        pausable.pause(pauseType2, true);
        vm.stopPrank();

        // Verify states
        assertTrue(pausable.paused(pauseType1));
        assertTrue(pausable.paused(pauseType2));
    }
}
