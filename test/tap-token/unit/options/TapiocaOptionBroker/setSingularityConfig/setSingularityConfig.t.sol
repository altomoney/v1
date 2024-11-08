// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_setSingularityConfigtree is Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.skip(true);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        // it should set singularity pool config
        // it should reset _totalSingularityPoolWeights
        // it should recalculate total weights for each singularity
        // it should emit SingularityConfigUpdate event with
        //     tSglAddress
        //     pool weight
        //     active status
        //     rescue status
        vm.skip(true);
    }

    function test_WhenPoolIsInRescueMode() external whenCallerIsOwner {
        // it should not sum the weight to total
        vm.skip(true);
    }

    function test_WhenPoolIsNotActive() external whenCallerIsOwner {
        // it should not sum the weight to total
        vm.skip(true);
    }

    function test_WhenPoolIsActiveAndNotInRescueMode() external whenCallerIsOwner {
        // it should add pool weight to total
        vm.skip(true);
    }
}
