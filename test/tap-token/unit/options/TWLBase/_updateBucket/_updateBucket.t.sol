// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {TWLBaseMock, Bucket} from "test/tap-token/mocks/TWLBaseMock.sol";
import {ITWLBase} from "contracts/tap-token/interfaces/ITWLBase.sol";

contract TWLBase_updateBucket is Test {
    TWLBaseMock twlBaseMock;

    function setUp() external {
        Bucket[] memory buckets = new Bucket[](2);
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
        buckets[1] = Bucket({
            enabled: true,
            epochGrowthRate: 2,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 10,
            rewardsMultiplier: 1,
            lockEpochDuration: 15,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1000
        });
        twlBaseMock = new TWLBaseMock(7 days, buckets);
    }

    function test_WhenRewardsMultiplierIsGreaterThan1e4() external {
        // it should revert with BUCKET_REWARDS_MULTIPLIER_MAX_REACHED
        vm.expectRevert(ITWLBase.BUCKET_REWARDS_MULTIPLIER_MAX_REACHED.selector);
        twlBaseMock.updateBucket(
            1,
            Bucket({
                enabled: true,
                epochGrowthRate: 1,
                epochDecayRate: 1,
                epochCeiling: 1,
                epochFloor: 1,
                rewardsMultiplier: 1e4 + 1,
                lockEpochDuration: 1,
                currentEpochInflows: 0,
                lastEpochInflows: 0,
                growthGoal: 1000
            })
        );
    }

    function test_WhenEpochFloorIsGreaterThanEpochCeiling() external {
        // it should revert with BUCKET_FLOOR_CEILING_MISMATCH
        vm.expectRevert(ITWLBase.BUCKET_FLOOR_CEILING_MISMATCH.selector);
        twlBaseMock.updateBucket(
            1,
            Bucket({
                enabled: true,
                epochGrowthRate: 1,
                epochDecayRate: 1,
                epochCeiling: 1,
                epochFloor: 2,
                rewardsMultiplier: 1,
                lockEpochDuration: 1,
                currentEpochInflows: 0,
                lastEpochInflows: 0,
                growthGoal: 1000
            })
        );
    }

    function test_WhenLockEpochDurationIsGreaterThanEpochCeiling() external {
        // it should revert with BUCKET_EPOCH_DURATION_CEILING_MISMATCH
        Bucket memory bucket = twlBaseMock.getBucket(1);
        bucket.epochCeiling = bucket.lockEpochDuration - 1;
        vm.expectRevert(ITWLBase.BUCKET_EPOCH_DURATION_CEILING_MISMATCH.selector);
        twlBaseMock.updateBucket(1, bucket);
    }

    function test_WhenLockEpochDurationIsLessThanEpochFloor() external {
        // it should revert with BUCKET_EPOCH_DURATION_FLOOR_MISMATCH
        Bucket memory currentBucket = twlBaseMock.getBucket(1);
        currentBucket.epochFloor = currentBucket.lockEpochDuration + 1;

        vm.expectRevert(ITWLBase.BUCKET_EPOCH_DURATION_FLOOR_MISMATCH.selector);
        twlBaseMock.updateBucket(1, currentBucket);
    }

    function test_WhenAllConditionsAreMet() external {
        // it should update the bucket at the given index
        // it should preserve the existing lockEpochDuration
        // it should preserve the existing currentEpochInflows
        // it should preserve the existing lastEpochInflows
        // it should emit a BucketUpdated event
        Bucket memory currentBucket = twlBaseMock.getBucket(1);

        vm.expectEmit(address(twlBaseMock));
        emit ITWLBase.BucketUpdated(1);

        twlBaseMock.updateBucket(
            1,
            Bucket({
                enabled: true,
                epochGrowthRate: 2,
                epochDecayRate: 3,
                epochCeiling: 100,
                epochFloor: 3,
                rewardsMultiplier: 6,
                lockEpochDuration: 100,
                currentEpochInflows: 200,
                lastEpochInflows: 300,
                growthGoal: 2000
            })
        );

        Bucket memory updatedBucket = twlBaseMock.getBucket(1);
        assertEq(updatedBucket.epochGrowthRate, 2);
        assertEq(updatedBucket.epochDecayRate, 3);
        assertEq(updatedBucket.epochCeiling, 100);
        assertEq(updatedBucket.epochFloor, 3);
        assertEq(updatedBucket.rewardsMultiplier, 6);
        assertEq(updatedBucket.growthGoal, 2000);
        assertEq(
            updatedBucket.lockEpochDuration,
            currentBucket.lockEpochDuration,
            "it should preserve the existing lockEpochDuration"
        );
        assertEq(
            updatedBucket.currentEpochInflows,
            currentBucket.currentEpochInflows,
            "it should preserve the existing currentEpochInflows"
        );
        assertEq(
            updatedBucket.lastEpochInflows,
            currentBucket.lastEpochInflows,
            "it should preserve the existing lastEpochInflows"
        );
    }
}
