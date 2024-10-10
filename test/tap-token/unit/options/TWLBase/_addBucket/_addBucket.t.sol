// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TWLBase, ITWLBase, Bucket} from "tap-token/governance/TWLBase.sol";
import {TWLBaseMock} from "test/tap-token/mocks/TWLBaseMock.sol";

contract TWLBase_addBucket is Test {
    TWLBaseMock twlBaseMock;

    function setUp() public {
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 1,
            rewardsMultiplier: 1,
            growthBufferPercent: 1,
            lockEpochDuration: 1,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });
        twlBaseMock = new TWLBaseMock(7 days, buckets);
    }

    function test_WhenBucketsLengthIsGreaterThanOrEqualToMAX_BUCKETS() external {
        // it should revert with MAX_BUCKETS_REACHED
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 1,
            rewardsMultiplier: 1,
            growthBufferPercent: 1,
            lockEpochDuration: 1,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });
        for (uint256 i = 0; i < twlBaseMock.MAX_BUCKETS() - 1; i++) {
            twlBaseMock.addBucket(bucket);
        }
        vm.expectRevert(ITWLBase.MAX_BUCKETS_REACHED.selector);
        twlBaseMock.addBucket(bucket);
    }

    function test_WhenRewardsMultiplierIsGreaterThan1e4() external {
        // it should revert with BUCKET_REWARDS_MULTIPLIER_MAX_REACHED
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 1,
            rewardsMultiplier: 1e4 + 1,
            growthBufferPercent: 1,
            lockEpochDuration: 1,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });

        vm.expectRevert(ITWLBase.BUCKET_REWARDS_MULTIPLIER_MAX_REACHED.selector);
        twlBaseMock.addBucket(bucket);
    }

    function test_WhenGrowthBufferPercentIsGreaterThan1e4() external {
        // it should revert with BUCKET_GROWTH_BUFFER_PERCENT_MAX_REACHED
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 1,
            rewardsMultiplier: 1,
            growthBufferPercent: 1e4 + 1,
            lockEpochDuration: 1,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });

        vm.expectRevert(ITWLBase.BUCKET_GROWTH_BUFFER_PERCENT_MAX_REACHED.selector);
        twlBaseMock.addBucket(bucket);
    }

    function test_WhenEpochFloorIsGreaterThanEpochCeiling() external {
        // it should revert with BUCKET_FLOOR_CEILING_MISMATCH
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 2,
            rewardsMultiplier: 1,
            growthBufferPercent: 1,
            lockEpochDuration: 1,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });

        vm.expectRevert(ITWLBase.BUCKET_FLOOR_CEILING_MISMATCH.selector);
        twlBaseMock.addBucket(bucket);
    }

    function test_WhenLockEpochDurationIsGreaterThanEpochCeiling() external {
        // it should revert with BUCKET_EPOCH_DURATION_CEILING_MISMATCH
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 5,
            epochFloor: 1,
            rewardsMultiplier: 1,
            growthBufferPercent: 1,
            lockEpochDuration: 10,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });

        vm.expectRevert(ITWLBase.BUCKET_EPOCH_DURATION_CEILING_MISMATCH.selector);
        twlBaseMock.addBucket(bucket);
    }

    function test_WhenLockEpochDurationIsLessThanEpochFloor() external {
        // it should revert with BUCKET_EPOCH_DURATION_FLOOR_MISMATCH
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 30,
            epochFloor: 20,
            rewardsMultiplier: 1,
            growthBufferPercent: 1,
            lockEpochDuration: 10,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });

        vm.expectRevert(ITWLBase.BUCKET_EPOCH_DURATION_FLOOR_MISMATCH.selector);
        twlBaseMock.addBucket(bucket);
    }

    function test_WhenAllConditionsAreMet() external {
        // it should add the new bucket to the buckets array
        // it should set totalDepositsLastEpoch to 0
        // it should set totalDeposits to 0
        // it should emit a BucketUpdated event
        Bucket memory bucket = Bucket({
            enabled: true,
            epochGrowthRate: 320,
            epochDecayRate: 1,
            epochCeiling: 1,
            epochFloor: 1,
            rewardsMultiplier: 1,
            growthBufferPercent: 1,
            lockEpochDuration: 1,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });

        vm.expectEmit(address(twlBaseMock));
        emit ITWLBase.BucketUpdated(1);

        assertEq(twlBaseMock.getBuckets().length, 1);
        twlBaseMock.addBucket(bucket);

        Bucket memory storedBucket = twlBaseMock.getBucket(1);
        assertEq(storedBucket.epochGrowthRate, 320, "EpochGrowthRate should match input");
        assertEq(storedBucket.totalDepositsLastEpoch, 0, "TotalDepositsLastEpoch should be set to 0 by default");
        assertEq(storedBucket.totalDeposits, 0, "TotalDeposits should be set to 0 by default");
        assertEq(twlBaseMock.getBuckets().length, 2);
    }
}
