// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PausableMock} from "./PausableMock.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SetPauserTest is Test {
    PausableMock internal pausable;
    address internal owner;
    address internal nonOwner;
    address internal pauser;
    bytes32 internal constant PAUSE_TYPE_ZERO = bytes32(0);
    bytes32 internal constant PAUSE_TYPE_ONE = bytes32(uint256(1));

    function setUp() public {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        pauser = makeAddr("pauser");
        pausable = new PausableMock(owner);
    }

    /*//////////////////////////////////////////////////////////////
                            REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_CallerIsNotOwner() public {
        // It should revert with OwnableUnauthorizedAccount
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address caller, address _pauser, bytes32 pauseType, bool status)
        public
    {
        vm.assume(caller != owner);

        // It should revert with OwnableUnauthorizedAccount
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        pausable.setPauser(_pauser, pauseType, status);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetPauser_WhenPauserIsZeroAddress() public {
        // It should set pauser status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(address(0), PAUSE_TYPE_ONE, true);
        pausable.setPauser(address(0), PAUSE_TYPE_ONE, true);

        assertTrue(pausable.pausers(address(0), PAUSE_TYPE_ONE));
    }

    function test_SetPauser_WhenPauseTypeIsZero_StatusFalse() public {
        // It should remove pauser status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ZERO, false);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, false);

        assertFalse(pausable.pausers(pauser, PAUSE_TYPE_ZERO));
    }

    function test_SetPauser_WhenPauseTypeIsZero_StatusTrue() public {
        // It should set pauser status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ZERO, true);
        pausable.setPauser(pauser, PAUSE_TYPE_ZERO, true);

        assertTrue(pausable.pausers(pauser, PAUSE_TYPE_ZERO));
    }

    function test_SetPauser_WhenPauseTypeIsNonZero_StatusFalse() public {
        // It should remove pauser status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, false);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, false);

        assertFalse(pausable.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function test_SetPauser_WhenPauseTypeIsNonZero_StatusTrue() public {
        // It should set pauser status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, true);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        assertTrue(pausable.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function test_SetPauser_ChangingFromTrueToFalse() public {
        // Setup: First set pauser to true
        vm.prank(owner);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);
        assertTrue(pausable.pausers(pauser, PAUSE_TYPE_ONE));

        // It should update status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, false);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, false);

        assertFalse(pausable.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function test_SetPauser_ChangingFromFalseToTrue() public {
        // Setup: Ensure pauser is false (default state)
        assertFalse(pausable.pausers(pauser, PAUSE_TYPE_ONE));

        // It should update status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, true);
        pausable.setPauser(pauser, PAUSE_TYPE_ONE, true);

        assertTrue(pausable.pausers(pauser, PAUSE_TYPE_ONE));
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetPauser_Success(address _pauser, bytes32 pauseType, bool status) public {
        // It should set pauser status and emit event
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(_pauser, pauseType, status);
        pausable.setPauser(_pauser, pauseType, status);

        assertEq(pausable.pausers(_pauser, pauseType), status);
    }

    function testFuzz_SetPauser_MultipleChanges(address _pauser, bytes32 pauseType) public {
        // Test multiple status changes
        vm.startPrank(owner);

        // Set to true
        pausable.setPauser(_pauser, pauseType, true);
        assertTrue(pausable.pausers(_pauser, pauseType));

        // Set to false
        pausable.setPauser(_pauser, pauseType, false);
        assertFalse(pausable.pausers(_pauser, pauseType));

        // Set back to true
        pausable.setPauser(_pauser, pauseType, true);
        assertTrue(pausable.pausers(_pauser, pauseType));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetPauser_MultiplePausersAndTypes() public {
        address pauser1 = makeAddr("pauser1");
        address pauser2 = makeAddr("pauser2");
        bytes32 pauseType1 = bytes32(uint256(1));
        bytes32 pauseType2 = bytes32(uint256(2));

        vm.startPrank(owner);

        // Set different pausers for different types
        pausable.setPauser(pauser1, pauseType1, true);
        pausable.setPauser(pauser2, pauseType2, true);
        pausable.setPauser(pauser1, pauseType2, true);

        vm.stopPrank();

        // Verify all are set correctly
        assertTrue(pausable.pausers(pauser1, pauseType1));
        assertTrue(pausable.pausers(pauser2, pauseType2));
        assertTrue(pausable.pausers(pauser1, pauseType2));
        assertFalse(pausable.pausers(pauser2, pauseType1));
    }
}
