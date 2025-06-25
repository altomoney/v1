// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {Bucket} from "@alto/rewards/interfaces/ITWLBase.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";

contract TWAlto_updateBucket is TWAltoBaseTest {
    Bucket validBucket;
    uint8 constant VALID_INDEX = 0; // Existing bucket index

    function setUp() public override {
        super.setUp();

        // Create a valid bucket for testing
        validBucket = Bucket({
            enabled: true, // Bucket is enabled
            epochGrowthRate: 2, // 2 epoch growth rate
            epochDecayRate: 1, // 1 epoch decay rate
            epochCeiling: 100, // Max 100 epochs
            epochFloor: 1, // Min 1 epoch (compatible with existing bucket)
            rewardsMultiplier: 500, // 5x multiplier (500 out of 10000)
            lockEpochDuration: 10, // Will be ignored/preserved
            currentEpochInflows: 999, // Will be ignored/preserved
            lastEpochInflows: 888, // Will be ignored/preserved
            growthGoal: 5000e18 // 5000 tokens growth goal
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

    modifier whenIndexIsOutOfBounds() {
        // Will be used in test with invalid index
        _;
    }

    modifier whenIndexIsValid() {
        // Will be used in tests with valid bucket index
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

    modifier whenExistingLockDurationExceedsCeiling() {
        // Will be used in test with existing bucket.lockEpochDuration > new bucket.epochCeiling
        _;
    }

    modifier whenExistingLockDurationBelowFloor() {
        // Will be used in test with existing bucket.lockEpochDuration < new bucket.epochFloor
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
        twAlto.updateBucket(VALID_INDEX, validBucket);
    }

    function test_RevertWhen_IndexIsOutOfBounds() public givenCallerIsOwner whenIndexIsOutOfBounds {
        uint8 invalidIndex = uint8(twAlto.getBuckets().length); // One beyond the last index

        // It should revert with array out of bounds
        vm.expectRevert();
        vm.prank(admin);
        twAlto.updateBucket(invalidIndex, validBucket);
    }

    function test_RevertWhen_BucketMultiplierExceedsMax()
        public
        givenCallerIsOwner
        whenIndexIsValid
        whenBucketMultiplierExceedsMax
    {
        Bucket memory invalidBucket = validBucket;
        invalidBucket.rewardsMultiplier = 10001; // Exceeds max of 1e4

        // It should revert with BUCKET_REWARDS_MULTIPLIER_MAX_REACHED
        vm.expectRevert();
        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, invalidBucket);
    }

    function test_RevertWhen_BucketFloorExceedsCeiling()
        public
        givenCallerIsOwner
        whenIndexIsValid
        whenBucketFloorExceedsCeiling
    {
        Bucket memory invalidBucket = validBucket;
        invalidBucket.epochFloor = 10;
        invalidBucket.epochCeiling = 5; // Floor > ceiling

        // It should revert with BUCKET_FLOOR_CEILING_MISMATCH
        vm.expectRevert();
        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, invalidBucket);
    }

    function test_RevertWhen_ExistingLockDurationExceedsCeiling()
        public
        givenCallerIsOwner
        whenIndexIsValid
        whenExistingLockDurationExceedsCeiling
    {
        // First, add a bucket with high lock duration
        Bucket memory highLockBucket = validBucket;
        highLockBucket.lockEpochDuration = 50;
        vm.prank(admin);
        twAlto.addBucket(highLockBucket);
        uint8 newBucketIndex = uint8(twAlto.getBuckets().length - 1);

        // Now try to update with lower ceiling
        Bucket memory invalidBucket = validBucket;
        invalidBucket.epochCeiling = 30; // Existing duration (50) > new ceiling (30)

        // It should revert with BUCKET_EPOCH_DURATION_CEILING_MISMATCH
        vm.expectRevert();
        vm.prank(admin);
        twAlto.updateBucket(newBucketIndex, invalidBucket);
    }

    function test_RevertWhen_ExistingLockDurationBelowFloor()
        public
        givenCallerIsOwner
        whenIndexIsValid
        whenExistingLockDurationBelowFloor
    {
        // First, add a bucket with low lock duration
        Bucket memory lowLockBucket = validBucket;
        lowLockBucket.lockEpochDuration = 2;
        lowLockBucket.epochFloor = 1; // Allow low duration initially
        vm.prank(admin);
        twAlto.addBucket(lowLockBucket);
        uint8 newBucketIndex = uint8(twAlto.getBuckets().length - 1);

        // Now try to update with higher floor
        Bucket memory invalidBucket = validBucket;
        invalidBucket.epochFloor = 5; // Existing duration (2) < new floor (5)

        // It should revert with BUCKET_EPOCH_DURATION_FLOOR_MISMATCH
        vm.expectRevert();
        vm.prank(admin);
        twAlto.updateBucket(newBucketIndex, invalidBucket);
    }

    function test_UpdateValidBucket() public givenCallerIsOwner whenIndexIsValid whenBucketIsValid {
        // Get original bucket
        Bucket memory originalBucket = twAlto.getBucket(VALID_INDEX);

        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, validBucket);

        // It should update bucket with new parameters
        Bucket memory updatedBucket = twAlto.getBucket(VALID_INDEX);
        assertEq(updatedBucket.enabled, validBucket.enabled);
        assertEq(updatedBucket.rewardsMultiplier, validBucket.rewardsMultiplier);
        assertEq(updatedBucket.epochFloor, validBucket.epochFloor);
        assertEq(updatedBucket.epochCeiling, validBucket.epochCeiling);
        assertEq(updatedBucket.epochGrowthRate, validBucket.epochGrowthRate);
        assertEq(updatedBucket.epochDecayRate, validBucket.epochDecayRate);
        assertEq(updatedBucket.growthGoal, validBucket.growthGoal);

        // It should preserve existing lockEpochDuration and inflows
        assertEq(updatedBucket.lockEpochDuration, originalBucket.lockEpochDuration);
        assertEq(updatedBucket.currentEpochInflows, originalBucket.currentEpochInflows);
        assertEq(updatedBucket.lastEpochInflows, originalBucket.lastEpochInflows);
    }

    function test_UpdateBucket_PreservesInflowData() public givenCallerIsOwner whenIndexIsValid whenBucketIsValid {
        // First, simulate some inflow activity by adding to bucket
        uint256 testAmount = 1000e18;
        alto.mint(alice, testAmount);
        vm.startPrank(alice);
        alto.approve(address(twAlto), testAmount);
        twAlto.participate(alice, testAmount, VALID_INDEX);
        vm.stopPrank();

        // Get bucket state after participation
        Bucket memory bucketAfterParticipation = twAlto.getBucket(VALID_INDEX);

        // Update bucket
        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, validBucket);

        // Verify inflow data is preserved
        Bucket memory updatedBucket = twAlto.getBucket(VALID_INDEX);
        assertEq(updatedBucket.currentEpochInflows, bucketAfterParticipation.currentEpochInflows);
        assertEq(updatedBucket.lastEpochInflows, bucketAfterParticipation.lastEpochInflows);
        assertEq(updatedBucket.lockEpochDuration, bucketAfterParticipation.lockEpochDuration);
    }

    function test_UpdateBucket_CanDisableBucket() public givenCallerIsOwner whenIndexIsValid whenBucketIsValid {
        // Update to disable bucket
        Bucket memory disabledBucket = validBucket;
        disabledBucket.enabled = false;

        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, disabledBucket);

        // Verify bucket is disabled
        Bucket memory updatedBucket = twAlto.getBucket(VALID_INDEX);
        assertFalse(updatedBucket.enabled);
    }

    function test_UpdateBucket_CanUpdateMultipleTimes() public givenCallerIsOwner whenIndexIsValid whenBucketIsValid {
        // First update
        Bucket memory firstUpdate = validBucket;
        firstUpdate.rewardsMultiplier = 1000;

        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, firstUpdate);

        Bucket memory afterFirst = twAlto.getBucket(VALID_INDEX);
        assertEq(afterFirst.rewardsMultiplier, 1000);

        // Second update
        Bucket memory secondUpdate = validBucket;
        secondUpdate.rewardsMultiplier = 2000;
        secondUpdate.epochCeiling = 200;

        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, secondUpdate);

        Bucket memory afterSecond = twAlto.getBucket(VALID_INDEX);
        assertEq(afterSecond.rewardsMultiplier, 2000);
        assertEq(afterSecond.epochCeiling, 200);
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_RevertWhen_CallerIsNotOwner(address _caller) public givenCallerIsNotOwner {
        vm.assume(_caller != admin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        vm.prank(_caller);
        twAlto.updateBucket(VALID_INDEX, validBucket);
    }

    function testFuzz_UpdateBucket_ValidParameters(
        uint16 _multiplier,
        uint24 _floor,
        uint24 _ceiling,
        uint256 _growthGoal
    ) public givenCallerIsOwner whenIndexIsValid whenBucketIsValid {
        // Bound to valid ranges
        _multiplier = uint16(bound(_multiplier, 1, 10000));
        _ceiling = uint24(bound(_ceiling, 1, 1000));
        _floor = uint24(bound(_floor, 1, _ceiling));
        _growthGoal = bound(_growthGoal, 1e18, 1000000e18);

        // Ensure existing lockEpochDuration is compatible
        Bucket memory originalBucket = twAlto.getBucket(VALID_INDEX);
        if (originalBucket.lockEpochDuration > _ceiling || originalBucket.lockEpochDuration < _floor) {
            // Skip this test case if existing duration is incompatible
            return;
        }

        Bucket memory fuzzBucket = validBucket;
        fuzzBucket.rewardsMultiplier = _multiplier;
        fuzzBucket.epochFloor = _floor;
        fuzzBucket.epochCeiling = _ceiling;
        fuzzBucket.growthGoal = _growthGoal;

        vm.prank(admin);
        twAlto.updateBucket(VALID_INDEX, fuzzBucket);

        // Verify bucket is updated correctly
        Bucket memory updatedBucket = twAlto.getBucket(VALID_INDEX);
        assertEq(updatedBucket.rewardsMultiplier, _multiplier);
        assertEq(updatedBucket.epochFloor, _floor);
        assertEq(updatedBucket.epochCeiling, _ceiling);
        assertEq(updatedBucket.growthGoal, _growthGoal);

        // Verify preserved fields
        assertEq(updatedBucket.lockEpochDuration, originalBucket.lockEpochDuration);
        assertEq(updatedBucket.currentEpochInflows, originalBucket.currentEpochInflows);
        assertEq(updatedBucket.lastEpochInflows, originalBucket.lastEpochInflows);
    }
}
