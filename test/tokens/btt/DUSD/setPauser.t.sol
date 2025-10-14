// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DUSDSetPauser is DUSDCommon {
    address constant PAUSER = address(0xb);
    bytes32 constant CUSTOM_PAUSE_TYPE = keccak256("CUSTOM_PAUSE");

    modifier whenCallerIsNotOwner() {
        // Use NON_OWNER which is already defined in DUSDCommon
        _;
    }

    modifier whenCallerIsOwner() {
        // OWNER is already set as the owner in DUSDCommon setup
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external whenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setPauser(PAUSER, PAUSE_TYPE, true);
    }

    function test_WhenSettingPauserForPauseTypeTrue() external whenCallerIsOwner {
        // Verify initial state
        assertFalse(dusd.pausers(PAUSER, PAUSE_TYPE));

        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);

        vm.prank(OWNER);
        dusd.setPauser(PAUSER, PAUSE_TYPE, true);

        // it should enable pauser for PAUSE_TYPE
        assertTrue(dusd.pausers(PAUSER, PAUSE_TYPE));
    }

    function test_WhenSettingPauserForPauseTypeFalse() external whenCallerIsOwner {
        // First enable the pauser
        vm.prank(OWNER);
        dusd.setPauser(PAUSER, PAUSE_TYPE, true);
        assertTrue(dusd.pausers(PAUSER, PAUSE_TYPE));

        // Then disable it
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, false);

        vm.prank(OWNER);
        dusd.setPauser(PAUSER, PAUSE_TYPE, false);

        // it should disable pauser for PAUSE_TYPE
        assertFalse(dusd.pausers(PAUSER, PAUSE_TYPE));
    }

    // Additional test cases for comprehensive coverage
    function test_WhenSettingPauserForCustomPauseTypeTrue() external whenCallerIsOwner {
        // Verify initial state
        assertFalse(dusd.pausers(PAUSER, CUSTOM_PAUSE_TYPE));

        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, CUSTOM_PAUSE_TYPE, true);

        vm.prank(OWNER);
        dusd.setPauser(PAUSER, CUSTOM_PAUSE_TYPE, true);

        // it should enable pauser for custom pause type
        assertTrue(dusd.pausers(PAUSER, CUSTOM_PAUSE_TYPE));
    }

    function test_WhenSettingPauserForCustomPauseTypeFalse() external whenCallerIsOwner {
        // First enable the pauser
        vm.prank(OWNER);
        dusd.setPauser(PAUSER, CUSTOM_PAUSE_TYPE, true);
        assertTrue(dusd.pausers(PAUSER, CUSTOM_PAUSE_TYPE));

        // Then disable it
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, CUSTOM_PAUSE_TYPE, false);

        vm.prank(OWNER);
        dusd.setPauser(PAUSER, CUSTOM_PAUSE_TYPE, false);

        // it should disable pauser for custom pause type
        assertFalse(dusd.pausers(PAUSER, CUSTOM_PAUSE_TYPE));
    }
}
