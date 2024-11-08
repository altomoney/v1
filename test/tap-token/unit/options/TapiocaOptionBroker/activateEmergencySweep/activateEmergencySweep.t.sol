// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_activateEmergencySweeptree is Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenCallerIsOwner() external {
        // it should set _lastEmergencySweep to current timestamp
        // it should emit ActivateEmergencySweep event
        vm.skip(true);
    }
}
