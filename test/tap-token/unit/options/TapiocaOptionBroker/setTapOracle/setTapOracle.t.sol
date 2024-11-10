// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_setTapOracletree is Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenCallerIsOwner() external {
        // it should set _tapOracle
        // it should set _tapOracleData
        // it should emit SetTapOracle event
        vm.skip(true);
    }
}
