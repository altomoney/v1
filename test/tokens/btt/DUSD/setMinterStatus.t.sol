// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DUSDSetMinterStatus is DUSDCommon {
    modifier givenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setMinterStatus(MINTER, true);
    }

    function test_WhenSettingMinterStatusToTrueForNewAddress() external givenCallerIsOwner {
        assertFalse(dusd.allowedMinter(MINTER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetMinterStatus(MINTER, true);

        vm.prank(OWNER);
        dusd.setMinterStatus(MINTER, true);

        // it should set allowedMinter mapping to true
        assertTrue(dusd.allowedMinter(MINTER));
    }

    function test_WhenSettingMinterStatusToFalseForExistingMinter() external givenCallerIsOwner {
        // First set as minter
        vm.prank(OWNER);
        dusd.setMinterStatus(MINTER, true);
        assertTrue(dusd.allowedMinter(MINTER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetMinterStatus(MINTER, false);

        vm.prank(OWNER);
        dusd.setMinterStatus(MINTER, false);

        // it should set allowedMinter mapping to false
        assertFalse(dusd.allowedMinter(MINTER));
    }

    function test_WhenSettingSameStatusTrueToTrue() external givenCallerIsOwner {
        // First set as minter
        vm.prank(OWNER);
        dusd.setMinterStatus(MINTER, true);
        assertTrue(dusd.allowedMinter(MINTER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetMinterStatus(MINTER, true);

        vm.prank(OWNER);
        dusd.setMinterStatus(MINTER, true);

        // it should update the mapping
        assertTrue(dusd.allowedMinter(MINTER));
    }

    function test_WhenSettingSameStatusFalseToFalse() external givenCallerIsOwner {
        assertFalse(dusd.allowedMinter(NON_MINTER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetMinterStatus(NON_MINTER, false);

        vm.prank(OWNER);
        dusd.setMinterStatus(NON_MINTER, false);

        // it should update the mapping
        assertFalse(dusd.allowedMinter(NON_MINTER));
    }
}
