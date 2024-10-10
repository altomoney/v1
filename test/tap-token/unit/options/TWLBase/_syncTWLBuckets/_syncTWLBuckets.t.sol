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
            growthBufferPercent: 10_00, // 10%
            lockEpochDuration: 20,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });
        bucketTwo = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 200,
            epochFloor: 50,
            rewardsMultiplier: 1,
            growthBufferPercent: 10_00, // 10%
            lockEpochDuration: 80,
            totalDepositsLastEpoch: 1,
            totalDeposits: 1
        });
        bucketsList.push(bucketOne);
        bucketsList.push(bucketTwo);

        Bucket[] memory emptyBuckets = new Bucket[](0);

        twlBaseMock = new TWLBaseMock(7 days, emptyBuckets);
    }

    modifier whenEachBucketIsDisabled() {
        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            bucket.enabled = false;
            twlBaseMock.updateBucket(i, bucket);
        }
        _;
    }

    modifier supplyInBuckets(uint256 amount) {
        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            twlBaseMock.supplyInBucket(amount, i);
            assertEq(twlBaseMock.getBucket(i).totalDeposits, bucket.totalDeposits + amount);
        }
        _;
    }

    modifier advanceEpoch(uint256 time) {
        vm.warp(block.timestamp + time);
        twlBaseMock.syncTWLBuckets();
        _;
    }

    modifier withdrawFromBuckets(uint256 amount) {
        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            twlBaseMock.withdrawFromBucket(amount, i);
            assertEq(twlBaseMock.getBucket(i).totalDeposits, bucket.totalDeposits - amount);
        }
        _;
    }

    function test_WhenLastEpochIsEqualToCurrentEpoch() external {
        // it should revert with EPOCH_NOT_FINISHED
        vm.expectRevert(ITWLBase.EPOCH_NOT_FINISHED.selector);
        twlBaseMock.syncTWLBuckets();
    }

    modifier whenLastEpochIsLessThanCurrentEpoch(uint256 time) {
        vm.warp(block.timestamp + time);

        uint256 currentEpoch = twlBaseMock.currentEpoch();
        uint256 lastEpoch = twlBaseMock.lastEpoch();

        assertLt(lastEpoch, currentEpoch);
        _;
    }

    function test_GivenAnEmptyBucketsArray() external whenLastEpochIsLessThanCurrentEpoch(14 days) {
        // it should only update lastEpoch
        assertEq(twlBaseMock.getBuckets().length, 0);

        assertEq(twlBaseMock.lastEpoch(), 0, "before sync lastEpoch");
        assertEq(twlBaseMock.currentEpoch(), 2, "before sync currentEpoch");
        twlBaseMock.syncTWLBuckets();

        assertEq(twlBaseMock.lastEpoch(), twlBaseMock.currentEpoch(), "after sync lastEpoch should match currentEpoch");
        assertEq(twlBaseMock.lastEpoch(), 2, "after sync lastEpoch");
    }

    modifier givenANon_emptyBucketsArray(Bucket[] storage buckets) {
        assertGt(buckets.length, 0, "Input bucket list should be greater than zero");

        for (uint256 i = 0; i < buckets.length; i++) {
            twlBaseMock.addBucket(buckets[i]);
        }
        _;
    }

    modifier whenEachBucketIsEnabled() {
        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            bucket.enabled = true;
            twlBaseMock.updateBucket(i, bucket);
        }
        _;
    }

    function test_WhenEachBucketIsEnabled()
        external
        whenLastEpochIsLessThanCurrentEpoch(14 days)
        givenANon_emptyBucketsArray(bucketsList)
        supplyInBuckets(100)
        whenEachBucketIsEnabled
    {
        // it should update totalDepositsLastEpoch |
        // it should update lastEpoch to currentEpoch

        assertEq(twlBaseMock.lastEpoch(), 0);
        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            assertEq(twlBaseMock.getBucket(i).totalDepositsLastEpoch, 0);
            assertEq(twlBaseMock.getBucket(i).totalDeposits, 100);
        }

        assertEq(twlBaseMock.lastEpoch(), 0);
        assertEq(twlBaseMock.currentEpoch(), 2);

        twlBaseMock.syncTWLBuckets();

        assertEq(twlBaseMock.lastEpoch(), twlBaseMock.currentEpoch());
        assertEq(twlBaseMock.lastEpoch(), 2);

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertEq(bucket.totalDepositsLastEpoch, 100);
            assertEq(bucket.totalDeposits, 100);
        }
    }

    function test_WhenTotalDepositsIsGreaterThanOrEqualToTotalDepositsLastEpoch()
        external
        whenLastEpochIsLessThanCurrentEpoch(7 days)
        givenANon_emptyBucketsArray(bucketsList)
        supplyInBuckets(100)
        whenEachBucketIsEnabled
    {
        // it should increase lockEpochDuration by epochGrowthRate

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertEq(bucket.lockEpochDuration, bucketsList[i].lockEpochDuration);
        }

        twlBaseMock.syncTWLBuckets();

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertGt(bucket.lockEpochDuration, bucketsList[i].lockEpochDuration);
            assertEq(bucket.lockEpochDuration, bucketsList[i].lockEpochDuration + bucketsList[i].epochGrowthRate);
        }
    }

    function test_WhenTotalDepositsIsLessThanTotalDepositsLastEpoch()
        external
        givenANon_emptyBucketsArray(bucketsList)
        whenEachBucketIsEnabled
        supplyInBuckets(100)
        advanceEpoch(8 days)
        withdrawFromBuckets(50)
        whenLastEpochIsLessThanCurrentEpoch(9 days)
    {
        // it should decrease lockEpochDuration by epochDecayRate
        Bucket[] memory previousBuckets = twlBaseMock.getBuckets();

        twlBaseMock.syncTWLBuckets();

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertLt(bucket.lockEpochDuration, previousBuckets[i].lockEpochDuration);
            assertEq(bucket.lockEpochDuration, previousBuckets[i].lockEpochDuration - bucketsList[i].epochDecayRate);
        }
    }

    function test_WhenLockEpochDurationIsGreaterThanEpochCeiling()
        external
        givenANon_emptyBucketsArray(bucketsList)
        whenEachBucketIsEnabled
        supplyInBuckets(100)
        whenLastEpochIsLessThanCurrentEpoch((bucketsList[1].epochCeiling * twlBaseMock.EPOCH_DURATION()) + 1)
    {
        // it should cap lockEpochDuration at epochCeiling |
        twlBaseMock.syncTWLBuckets();

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertEq(bucket.lockEpochDuration, bucketsList[i].epochCeiling);
        }
    }

    function test_WhenLockEpochDurationIsLessThanEpochFloor()
        external
        givenANon_emptyBucketsArray(bucketsList)
        whenEachBucketIsEnabled
        supplyInBuckets(100e6)
        advanceEpoch(7 days)
        withdrawFromBuckets(50e6)
        whenLastEpochIsLessThanCurrentEpoch(250 days)
    {
        // it should floor lockEpochDuration at epochFloor |
        twlBaseMock.syncTWLBuckets();

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertEq(bucket.lockEpochDuration, bucketsList[i].epochFloor, vm.toString(uint256(i)));
        }
    }

    function test_WhenEachBucketIsDisabled()
        external
        whenLastEpochIsLessThanCurrentEpoch(7 days)
        supplyInBuckets(100e6)
        givenANon_emptyBucketsArray(bucketsList)
        whenEachBucketIsDisabled
    {
        // it should update totalDepositsLastEpoch
        // it should update lastEpoch to currentEpoch

        Bucket[] memory pastBuckets = twlBaseMock.getBuckets();

        assertEq(twlBaseMock.currentEpoch(), 1);
        assertEq(twlBaseMock.lastEpoch(), 0);

        twlBaseMock.syncTWLBuckets();

        for (uint8 i = 0; i < twlBaseMock.getBuckets().length; i++) {
            Bucket memory bucket = twlBaseMock.getBucket(i);
            assertEq(bucket.totalDepositsLastEpoch, pastBuckets[i].totalDeposits);
            assertEq(twlBaseMock.lastEpoch(), twlBaseMock.currentEpoch());
        }
    }
}
