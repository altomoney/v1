// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSDCommon} from "../SDUSDCommon.t.sol";

contract SDUSD_SetPauser_Test is SDUSDCommon {
    bytes32 internal constant OTHER_PAUSE_TYPE = keccak256("OTHER_PAUSE_TYPE");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        vault.setPauser(NEW_PAUSER, PAUSE_TYPE, true);
    }

    function test_EnablesPauserAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.PauserUpdated(NEW_PAUSER, PAUSE_TYPE, true);
        vm.prank(ADMIN);
        vault.setPauser(NEW_PAUSER, PAUSE_TYPE, true);
        assertTrue(vault.pausers(NEW_PAUSER, PAUSE_TYPE));
    }

    function test_DisablesPauserAndEmitsEvent() public {
        vm.prank(ADMIN);
        vault.setPauser(NEW_PAUSER, PAUSE_TYPE, true);
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.PauserUpdated(NEW_PAUSER, PAUSE_TYPE, false);
        vm.prank(ADMIN);
        vault.setPauser(NEW_PAUSER, PAUSE_TYPE, false);
        assertFalse(vault.pausers(NEW_PAUSER, PAUSE_TYPE));
    }

    function test_AllowsZeroAddressPauserAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.PauserUpdated(address(0), PAUSE_TYPE, true);
        vm.prank(ADMIN);
        vault.setPauser(address(0), PAUSE_TYPE, true);
        assertTrue(vault.pausers(address(0), PAUSE_TYPE));
    }

    function test_SettingSameStatusSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);
        vm.prank(ADMIN);
        vault.setPauser(PAUSER, PAUSE_TYPE, true);
        assertTrue(vault.pausers(PAUSER, PAUSE_TYPE));
    }

    function test_UpdatesOnlySpecifiedPauseType() public {
        vm.prank(ADMIN);
        vault.setPauser(NEW_PAUSER, OTHER_PAUSE_TYPE, true);
        assertTrue(vault.pausers(NEW_PAUSER, OTHER_PAUSE_TYPE));
        assertFalse(vault.pausers(NEW_PAUSER, PAUSE_TYPE));
    }
}
