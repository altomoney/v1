// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DUSDSetBurnerStatus is DUSDCommon {
    modifier givenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setBurnerStatus(BURNER, true);
    }

    function test_WhenSettingBurnerStatusToTrueForNewAddress() external givenCallerIsOwner {
        assertFalse(dusd.allowedBurner(BURNER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetBurnerStatus(BURNER, true);

        vm.prank(OWNER);
        dusd.setBurnerStatus(BURNER, true);

        // it should set allowedBurner mapping to true
        assertTrue(dusd.allowedBurner(BURNER));
    }

    function test_WhenSettingBurnerStatusToFalseForExistingBurner() external givenCallerIsOwner {
        // First set as burner
        vm.prank(OWNER);
        dusd.setBurnerStatus(BURNER, true);
        assertTrue(dusd.allowedBurner(BURNER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetBurnerStatus(BURNER, false);

        vm.prank(OWNER);
        dusd.setBurnerStatus(BURNER, false);

        // it should set allowedBurner mapping to false
        assertFalse(dusd.allowedBurner(BURNER));
    }

    function test_WhenSettingSameStatusTrueToTrue() external givenCallerIsOwner {
        // First set as burner
        vm.prank(OWNER);
        dusd.setBurnerStatus(BURNER, true);
        assertTrue(dusd.allowedBurner(BURNER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetBurnerStatus(BURNER, true);

        vm.prank(OWNER);
        dusd.setBurnerStatus(BURNER, true);

        // it should update the mapping
        assertTrue(dusd.allowedBurner(BURNER));
    }

    function test_WhenSettingSameStatusFalseToFalse() external givenCallerIsOwner {
        assertFalse(dusd.allowedBurner(NON_BURNER));

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetBurnerStatus(NON_BURNER, false);

        vm.prank(OWNER);
        dusd.setBurnerStatus(NON_BURNER, false);

        // it should update the mapping
        assertFalse(dusd.allowedBurner(NON_BURNER));
    }
}
