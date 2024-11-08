// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_setPausetree is Test {
    function test_WhenCallerIsNotAuthorized() external {
        // it should revert with NotAuthorized
        vm.skip(true);
    }

    modifier whenCallerIsAuthorized() {
        _;
    }

    function test_WhenPauseStateIsTrue() external whenCallerIsAuthorized {
        // it should pause contract
        // it should emit Pause event with true
        vm.skip(true);
    }

    function test_WhenPauseStateIsFalse() external whenCallerIsAuthorized {
        // it should unpause contract
        // it should emit Pause event with false
        vm.skip(true);
    }
}
