// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_setExerciseWindowtree is Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenCallerIsOwner() external {
        // it should set _exerciseWindow
        // it should emit SetExerciseWindow event
        vm.skip(true);
    }
}
