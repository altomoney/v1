// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_setClustertree is Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenClusterAddressIsZero() external {
        // it should revert with NotValid
        vm.skip(true);
    }

    function test_WhenConditionsAreMet() external {
        // it should set _cluster
        // it should emit SetCluster event
        vm.skip(true);
    }
}
