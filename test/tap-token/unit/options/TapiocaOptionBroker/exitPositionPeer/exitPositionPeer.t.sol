// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_exitPositionPeertree is Test {
    function test_RevertWhen_ContractIsPaused() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenCallerIsNotMAGNETAR() external {
        // it should revert with NotAuthorized
        vm.skip(true);
    }

    function test_WhenPositionHasNotExpired() external {
        // it should revert with LockNotExpired
        vm.skip(true);
    }

    function test_WhenAllConditionsAreMet() external {
        // it should store sglShares amount
        // it should reset position's sglShares to 0
        // it should transfer sglShares to caller
        // it should emit ExitPosition event with
        //     from address
        //     bucketId
        //     tSGLAddress
        //     currentEpoch
        //     sglShares amount
        vm.skip(true);
    }
}
