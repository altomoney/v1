// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_advanceWeektree is Test {
    function test_WhenLastEpochEqualsCurrentEpoch() external {
        // it should revert with NotValid
        vm.skip(true);
    }

    modifier whenLastEpochIsNotCurrentEpoch() {
        _;
    }

    function test_WhenLastEpochIsNotCurrentEpoch() external whenLastEpochIsNotCurrentEpoch {
        // it should sync TWL buckets
        // it should extract TAP from TAP_TOKEN
        // it should emit TAP to gauges
        // it should update lastEpoch
        // it should emit NewEpoch event with
        //     lastEpoch
        //     epochTAP
        //     _epochTAPValuation
        vm.skip(true);
    }

    modifier whenGettingTAPValuation() {
        _;
    }

    function test_WhenTapOracleCallSucceeds() external whenLastEpochIsNotCurrentEpoch whenGettingTAPValuation {
        // it should set _epochTAPValuation
        vm.skip(true);
    }

    function test_WhenTapOracleCallFails() external whenLastEpochIsNotCurrentEpoch whenGettingTAPValuation {
        // it should revert with Failed
        vm.skip(true);
    }
}
