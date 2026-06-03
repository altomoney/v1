// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

contract SetPauserTest is WrapperTokenCommon {
    bytes32 internal constant PAUSE_TYPE_ZERO = bytes32(0);
    bytes32 internal constant PAUSE_TYPE_ONE = bytes32(uint256(1));

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        wrapper.setPauser(pauser, PAUSE_TYPE_ONE, true);
    }

    function test_SetPauser_WhenPauserIsZeroAddress() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(address(0), PAUSE_TYPE_ONE, true);
        wrapper.setPauser(address(0), PAUSE_TYPE_ONE, true);

        assertTrue(wrapper.pausers(address(0), PAUSE_TYPE_ONE));
    }

    function test_SetPauser_WhenPauseTypeIsZero_StatusFalse() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ZERO, false);
        wrapper.setPauser(pauser, PAUSE_TYPE_ZERO, false);

        assertFalse(wrapper.pausers(pauser, PAUSE_TYPE_ZERO));
    }

    function test_SetPauser_WhenPauseTypeIsZero_StatusTrue() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ZERO, true);
        wrapper.setPauser(pauser, PAUSE_TYPE_ZERO, true);

        assertTrue(wrapper.pausers(pauser, PAUSE_TYPE_ZERO));
    }

    function test_SetPauser_WhenPauseTypeIsNonZero_StatusFalse() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, false);
        wrapper.setPauser(pauser, PAUSE_TYPE_ONE, false);

        assertFalse(wrapper.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function test_SetPauser_WhenPauseTypeIsNonZero_StatusTrue() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, true);
        wrapper.setPauser(pauser, PAUSE_TYPE_ONE, true);

        assertTrue(wrapper.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function test_SetPauser_ChangingFromTrueToFalse() public {
        vm.startPrank(owner);
        wrapper.setPauser(pauser, PAUSE_TYPE_ONE, true);
        assertTrue(wrapper.pausers(pauser, PAUSE_TYPE_ONE));

        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, false);
        wrapper.setPauser(pauser, PAUSE_TYPE_ONE, false);
        vm.stopPrank();

        assertFalse(wrapper.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function test_SetPauser_ChangingFromFalseToTrue() public {
        assertFalse(wrapper.pausers(pauser, PAUSE_TYPE_ONE));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE_ONE, true);
        wrapper.setPauser(pauser, PAUSE_TYPE_ONE, true);

        assertTrue(wrapper.pausers(pauser, PAUSE_TYPE_ONE));
    }

    function testFuzz_SetPauser_Success(address _pauser, bytes32 pauseType, bool status) public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(_pauser, pauseType, status);
        wrapper.setPauser(_pauser, pauseType, status);

        assertEq(wrapper.pausers(_pauser, pauseType), status);
    }
}
