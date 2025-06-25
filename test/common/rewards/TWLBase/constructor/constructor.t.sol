// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TWLBase, ITWLBase, Bucket} from "@alto/rewards/TWLBase.sol";
import {TWLBaseMock} from "../TWLBaseMock.sol";

contract TWLBase_constructor is Test {
    function test_RevertWhen__epochDurationIsZero() external {
        // it should revert
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);
        vm.expectRevert(ITWLBase.EPOCH_DURATION_ZERO.selector);
        new TWLBaseMock(0, buckets);
    }

    function test_When_epochDurationIsNon_zero() external {
        // it should set EPOCH_DURATION
        // it should set INIT_TIMESTAMP
        // it should add all provided buckets
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 1,
            rewardsMultiplier: 1,
            lockEpochDuration: 1,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1000
        });
        TWLBaseMock twlBaseMock = new TWLBaseMock(7 days, buckets);
        assertEq(twlBaseMock.EPOCH_DURATION(), 7 days);
        assertEq(twlBaseMock.INIT_TIMESTAMP(), block.timestamp);
        assertEq(twlBaseMock.currentEpoch(), 0);
        assertEq(twlBaseMock.lastEpoch(), 0);
        assertEq(twlBaseMock.getBuckets().length, 1);
    }

    function test_WhenAnEmpty_bucketsArray() external {
        // it should not add any buckets
        Bucket[] memory buckets = new Bucket[](0);
        TWLBaseMock twlBaseMock = new TWLBaseMock(7 days, buckets);
        assertEq(twlBaseMock.EPOCH_DURATION(), 7 days);
        assertEq(twlBaseMock.INIT_TIMESTAMP(), block.timestamp);
        assertEq(twlBaseMock.getBuckets().length, 0);
        assertEq(twlBaseMock.currentEpoch(), 0);
        assertEq(twlBaseMock.lastEpoch(), 0);
    }

    function test_WhenANon_empty_bucketsArray() external {
        // it should call _addBucket for each bucket
        Bucket[] memory buckets = new Bucket[](3);
        buckets[0] = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);
        buckets[1] = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);
        buckets[2] = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);

        TWLBaseMock twlBaseMock = new TWLBaseMock(7 days, buckets);
        assertEq(twlBaseMock.getBucket(0).enabled, buckets[0].enabled);
        assertEq(twlBaseMock.getBuckets().length, 3);
    }
}
