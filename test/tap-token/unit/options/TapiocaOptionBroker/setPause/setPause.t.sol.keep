// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";
import {ITapiocaOptionBroker} from "tap-token/interfaces/ITapiocaOptionBroker.sol";

contract TapiocaOptionBrokerSetPauseTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert(ITapiocaOptionBroker.NotAuthorized.selector);
        tob.setPause(true);
        vm.stopPrank();
    }

    function test_setPause_whenClusterPauser() public {
        address pauser = makeAddr("pauser");

        // Set up pauser role
        bytes32 pauserRole = keccak256("PAUSABLE");

        vm.prank(cluster.owner());
        cluster.setRoleForContract(address(pauser), pauserRole, true);

        vm.startPrank(pauser);
        tob.setPause(true);
        assertTrue(tob.paused(), "Contract should be paused");
        vm.stopPrank();
    }

    function test_setPause_whenPausingContract() public {
        vm.startPrank(owner);
        tob.setPause(true);
        assertTrue(tob.paused(), "Contract should be paused");
        vm.stopPrank();
    }

    function test_setPause_whenUnpausingContract() public {
        // First pause
        vm.startPrank(owner);
        tob.setPause(true);
        assertTrue(tob.paused(), "Contract should be paused");

        // Then unpause
        tob.setPause(false);
        assertFalse(tob.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }
}
