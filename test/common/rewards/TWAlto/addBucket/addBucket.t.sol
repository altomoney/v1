// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {Bucket} from "@alto/rewards/interfaces/ITWLBase.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";

contract TWAlto_addBucket is TWAltoBaseTest {
    Bucket validBucket;

    function setUp() public override {
        super.setUp();

        // Create a valid bucket for testing
        validBucket = Bucket({
            enabled: true, // Bucket is enabled
            epochGrowthRate: 1, // 1 epoch growth rate
            epochDecayRate: 1, // 1 epoch decay rate
            epochCeiling: 52, // Max 52 epochs (1 year)
            epochFloor: 1, // Min 1 epoch
            rewardsMultiplier: 200, // 2x multiplier (200 out of 10000)
            lockEpochDuration: 2, // 2 epochs lock duration
            currentEpochInflows: 0, // Will be set by contract
            lastEpochInflows: 0, // Will be set by contract
            growthGoal: 1000e18 // 1000 tokens growth goal
        });
    }

    // ====================================
    //           MODIFIERS
    // ====================================

    modifier givenCallerIsNotOwner() {
        // Will use alice (not owner) in tests
        _;
    }

    modifier givenCallerIsOwner() {
        // Will use admin (owner) in tests
        _;
    }

    modifier whenBucketMultiplierIsZero() {
        // Will be used in test with bucket.rewardsMultiplier = 0
        _;
    }

    modifier whenBucketMultiplierExceedsMax() {
        // Will be used in test with bucket.rewardsMultiplier > 1e4
        _;
    }

    modifier whenBucketFloorExceedsCeiling() {
        // Will be used in test with bucket.epochFloor > bucket.epochCeiling
        _;
    }

    modifier whenBucketLockDurationExceedsCeiling() {
        // Will be used in test with bucket.lockEpochDuration > bucket.epochCeiling
        _;
    }

    modifier whenBucketLockDurationBelowFloor() {
        // Will be used in test with bucket.lockEpochDuration < bucket.epochFloor
        _;
    }

    modifier whenBucketIsValid() {
        // Will be used in tests with valid bucket parameters
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_CallerIsNotOwner() public givenCallerIsNotOwner {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        twAlto.addBucket(validBucket);
    }

    function test_RevertWhen_BucketMultiplierExceedsMax() public givenCallerIsOwner whenBucketMultiplierExceedsMax {
        Bucket memory invalidBucket = validBucket;
        invalidBucket.rewardsMultiplier = 10001; // Exceeds max of 1e4

        // It should revert with BUCKET_REWARDS_MULTIPLIER_MAX_REACHED
        vm.expectRevert();
        vm.prank(admin);
        twAlto.addBucket(invalidBucket);
    }

    function test_RevertWhen_BucketFloorExceedsCeiling() public givenCallerIsOwner whenBucketFloorExceedsCeiling {
        Bucket memory invalidBucket = validBucket;
        invalidBucket.epochFloor = 10;
        invalidBucket.epochCeiling = 5; // Floor > ceiling

        // It should revert with BUCKET_FLOOR_CEILING_MISMATCH
        vm.expectRevert();
        vm.prank(admin);
        twAlto.addBucket(invalidBucket);
    }

    function test_RevertWhen_BucketLockDurationExceedsCeiling()
        public
        givenCallerIsOwner
        whenBucketLockDurationExceedsCeiling
    {
        Bucket memory invalidBucket = validBucket;
        invalidBucket.lockEpochDuration = 100;
        invalidBucket.epochCeiling = 50; // Duration > ceiling

        // It should revert with BUCKET_EPOCH_DURATION_CEILING_MISMATCH
        vm.expectRevert();
        vm.prank(admin);
        twAlto.addBucket(invalidBucket);
    }

    function test_RevertWhen_BucketLockDurationBelowFloor()
        public
        givenCallerIsOwner
        whenBucketLockDurationBelowFloor
    {
        Bucket memory invalidBucket = validBucket;
        invalidBucket.lockEpochDuration = 1;
        invalidBucket.epochFloor = 5; // Duration < floor

        // It should revert with BUCKET_EPOCH_DURATION_FLOOR_MISMATCH
        vm.expectRevert();
        vm.prank(admin);
        twAlto.addBucket(invalidBucket);
    }

    function test_AddValidBucket() public givenCallerIsOwner whenBucketIsValid {
        uint256 bucketCountBefore = twAlto.getBuckets().length;

        vm.prank(admin);
        twAlto.addBucket(validBucket);

        // It should increase bucket count
        assertEq(twAlto.getBuckets().length, bucketCountBefore + 1);

        // It should store bucket with correct parameters
        Bucket memory addedBucket = twAlto.getBucket(uint8(bucketCountBefore));
        assertEq(addedBucket.enabled, validBucket.enabled);
        assertEq(addedBucket.rewardsMultiplier, validBucket.rewardsMultiplier);
        assertEq(addedBucket.lockEpochDuration, validBucket.lockEpochDuration);
        assertEq(addedBucket.epochFloor, validBucket.epochFloor);
        assertEq(addedBucket.epochCeiling, validBucket.epochCeiling);
    }

    function test_AddMultipleBuckets() public givenCallerIsOwner whenBucketIsValid {
        uint256 initialCount = twAlto.getBuckets().length;

        Bucket memory bucket1 = validBucket;
        bucket1.rewardsMultiplier = 100; // 1x multiplier
        bucket1.lockEpochDuration = 1;

        Bucket memory bucket2 = validBucket;
        bucket2.rewardsMultiplier = 300; // 3x multiplier
        bucket2.lockEpochDuration = 4;

        // Add first bucket
        vm.prank(admin);
        twAlto.addBucket(bucket1);

        // Add second bucket
        vm.prank(admin);
        twAlto.addBucket(bucket2);

        // Verify total count
        assertEq(twAlto.getBuckets().length, initialCount + 2);

        // Verify each bucket is stored correctly
        Bucket memory storedBucket1 = twAlto.getBucket(uint8(initialCount));
        assertEq(storedBucket1.rewardsMultiplier, 100);
        assertEq(storedBucket1.lockEpochDuration, 1);

        Bucket memory storedBucket2 = twAlto.getBucket(uint8(initialCount + 1));
        assertEq(storedBucket2.rewardsMultiplier, 300);
        assertEq(storedBucket2.lockEpochDuration, 4);
    }

    function test_AddBucket_SetsInflowsToZero() public givenCallerIsOwner whenBucketIsValid {
        uint256 bucketCountBefore = twAlto.getBuckets().length;

        vm.prank(admin);
        twAlto.addBucket(validBucket);

        // Verify inflows are reset to zero regardless of input
        Bucket memory addedBucket = twAlto.getBucket(uint8(bucketCountBefore));
        assertEq(addedBucket.currentEpochInflows, 0);
        assertEq(addedBucket.lastEpochInflows, 0);
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_RevertWhen_CallerIsNotOwner(address _caller) public givenCallerIsNotOwner {
        vm.assume(_caller != admin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        vm.prank(_caller);
        twAlto.addBucket(validBucket);
    }

    function testFuzz_AddBucket_ValidParameters(
        uint16 _multiplier,
        uint24 _lockDuration,
        uint24 _floor,
        uint24 _ceiling
    ) public givenCallerIsOwner whenBucketIsValid {
        // Bound to valid ranges
        _multiplier = uint16(bound(_multiplier, 1, 10000));
        _ceiling = uint24(bound(_ceiling, 1, 1000));
        _floor = uint24(bound(_floor, 1, _ceiling));
        _lockDuration = uint24(bound(_lockDuration, _floor, _ceiling));

        Bucket memory fuzzBucket = validBucket;
        fuzzBucket.rewardsMultiplier = _multiplier;
        fuzzBucket.lockEpochDuration = _lockDuration;
        fuzzBucket.epochFloor = _floor;
        fuzzBucket.epochCeiling = _ceiling;

        uint256 bucketCountBefore = twAlto.getBuckets().length;

        vm.prank(admin);
        twAlto.addBucket(fuzzBucket);

        // Verify bucket is added correctly
        assertEq(twAlto.getBuckets().length, bucketCountBefore + 1);

        Bucket memory addedBucket = twAlto.getBucket(uint8(bucketCountBefore));
        assertEq(addedBucket.rewardsMultiplier, _multiplier);
        assertEq(addedBucket.lockEpochDuration, _lockDuration);
        assertEq(addedBucket.epochFloor, _floor);
        assertEq(addedBucket.epochCeiling, _ceiling);
    }
}
