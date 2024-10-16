// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TWLBaseMock, Bucket} from "test/tap-token/mocks/TWLBaseMock.sol";
import {ITWLBase} from "tap-token/interfaces/ITWLBase.sol";

contract TWLBase_syncTWLBuckets is Test {
    TWLBaseMock twlBaseMock;

    Bucket bucketOne;
    Bucket bucketTwo;

    Bucket[] bucketsList;

    function setUp() external {
        bucketOne = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 10,
            rewardsMultiplier: 1,
            lockEpochDuration: 20,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1000
        });
        bucketTwo = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 200,
            epochFloor: 50,
            rewardsMultiplier: 1,
            lockEpochDuration: 80,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1000
        });
        bucketsList.push(bucketOne);
        bucketsList.push(bucketTwo);

        twlBaseMock = new TWLBaseMock(7 days, bucketsList);
    }

    function test_WhenLastEpochIsEqualToCurrentEpoch() external {
        // it should revert with EPOCH_NOT_FINISHED
        vm.expectRevert(ITWLBase.EPOCH_NOT_FINISHED.selector);
        twlBaseMock.syncTWLBuckets(1);
    }

    function test_WhenCurrentEpochInflowsIsGreaterThanOrEqualToLastEpochInflowsPlusGrowthGoal() external {
        // it should increase lockEpochDuration by epochGrowthRate
        vm.warp(block.timestamp + 7 days);
        twlBaseMock.supplyInBucket(2000, 0);
        twlBaseMock.syncTWLBuckets(1);

        Bucket memory updatedBucket = twlBaseMock.getBucket(0);
        assertEq(updatedBucket.lockEpochDuration, 21);
    }

    function test_WhenCurrentEpochInflowsIsLessThanLastEpochInflowsPlusGrowthGoal() external {
        // it should decrease lockEpochDuration by epochDecayRate
        vm.warp(block.timestamp + 7 days);
        twlBaseMock.supplyInBucket(500, 0);
        twlBaseMock.syncTWLBuckets(1);

        Bucket memory updatedBucket = twlBaseMock.getBucket(0);
        assertEq(updatedBucket.lockEpochDuration, 19);
    }

    function test_WhenCurrentEpochInflowsIsLessThanLastEpochInflowsPlusGrowthGoalAndEpochDecayRateTimesMissingEpochsIsGreaterThanLockEpochDuration() external {
        // it should set lockEpochDuration to zero and replaced by the epochFloor
        vm.warp(block.timestamp + 7 days);
        Bucket memory bucket = twlBaseMock.getBucket(0);
        bucket.epochDecayRate = 10000;
        twlBaseMock.updateBucket(0, bucket);

        twlBaseMock.syncTWLBuckets(1);

        Bucket memory updatedBucket = twlBaseMock.getBucket(0);
        assertEq(updatedBucket.lockEpochDuration, updatedBucket.epochFloor);
    }


    function test_WhenLockEpochDurationIsGreaterThanEpochCeiling() external {
        // it should cap lockEpochDuration at epochCeiling
        for (uint256 i = 0; i < 100; i++) {
            twlBaseMock.supplyInBucket(2000e18 + (2000 * i), 0);
            vm.warp(block.timestamp + 7 days);
            twlBaseMock.syncTWLBuckets(1);
        }

        Bucket memory updatedBucket = twlBaseMock.getBucket(0);
        assertEq(updatedBucket.lockEpochDuration, updatedBucket.epochCeiling);
    }

    function test_WhenLockEpochDurationIsLessThanEpochFloor() external {
        // it should floor lockEpochDuration at epochFloor
        vm.warp(block.timestamp + 7 days);
        for (uint256 i = 0; i < 100; i++) {
            vm.warp(block.timestamp + 7 days);
            twlBaseMock.syncTWLBuckets(1);
        }

        Bucket memory updatedBucket = twlBaseMock.getBucket(0);
        assertEq(updatedBucket.lockEpochDuration, updatedBucket.epochFloor);
    }

    function test_WhenLimitInputIsZero() external {
        // it should not update the bucket and revert with LIMIT_IS_ZERO
        vm.expectRevert(ITWLBase.LIMIT_IS_ZERO.selector);
        twlBaseMock.syncTWLBuckets(0);
    }

    function test_WhenBucketIsDisabled() external {
        // it should not update the bucket
        twlBaseMock.supplyInBucket(2000, 0);
        vm.warp(block.timestamp + 7 days);

        Bucket memory bucket = twlBaseMock.getBucket(0);
        bucket.enabled = false;

        twlBaseMock.updateBucket(0, bucket);

        twlBaseMock.syncTWLBuckets(1);

        Bucket memory updatedBucket = twlBaseMock.getBucket(0);
        assertEq(updatedBucket.lockEpochDuration, bucket.lockEpochDuration);
    }
}
