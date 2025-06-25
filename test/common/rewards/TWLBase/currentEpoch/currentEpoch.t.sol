// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {TWLBaseMock, Bucket} from "../TWLBaseMock.sol";

contract TWLBase_currentEpoch is Test {
    TWLBaseMock twlBaseMock;

    function setUp() public {
        Bucket[] memory buckets = new Bucket[](0);
        twlBaseMock = new TWLBaseMock(7 days, buckets);
    }

    function test_WhenDeployed() external {
        // it should return 0
        assertEq(twlBaseMock.currentEpoch(), 0);
    }

    function test_WhenCurrentTimeIsAfter29Days() external {
        // it should return the correct epoch number based on INIT_TIMESTAMP and EPOCH_DURATION
        // it should handle epoch transitions correctly
        vm.warp(block.timestamp + 29 days);
        assertEq(twlBaseMock.currentEpoch(), 4);
    }

    function test_WhenCurrentTimeIsAfter28Days() external {
        // it should return the correct epoch number based on INIT_TIMESTAMP and EPOCH_DURATION
        // it should handle epoch transitions correctly
        vm.warp(block.timestamp + 28 days);
        assertEq(twlBaseMock.currentEpoch(), 4);
    }

    function test_WhenCurrentTimeIsAfter27Days() external {
        // it should return the correct epoch number based on INIT_TIMESTAMP and EPOCH_DURATION
        // it should handle epoch transitions correctly
        vm.warp(block.timestamp + 27 days);
        assertEq(twlBaseMock.currentEpoch(), 3);
    }
}
