// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {TWLBaseMock, Bucket} from "test/tap-token/mocks/TWLBaseMock.sol";
import {ITWLBase} from "tap-token/interfaces/ITWLBase.sol";
import {stdError} from "forge-std/StdError.sol";

contract TWLBase_supplyInBucket is Test {
    modifier givenBucketIsEnabled(uint8 bucketId) {
        Bucket memory bucket = twlBaseMock.getBucket(bucketId);
        bucket.enabled = true;
        twlBaseMock.updateBucket(bucketId, bucket);
        _;
    }

    modifier givenBucketIsDisabled(uint8 bucketId) {
        Bucket memory bucket = twlBaseMock.getBucket(bucketId);
        bucket.enabled = false;
        twlBaseMock.updateBucket(bucketId, bucket);
        _;
    }

    TWLBaseMock twlBaseMock;

    function setUp() external {
        Bucket[] memory buckets = new Bucket[](2);
        buckets[0] = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);
        buckets[1] = Bucket(true, 2, 1, 1, 1, 1, 1, 1, 1, 1);
        twlBaseMock = new TWLBaseMock(7 days, buckets);
    }

    function test_WhenAmountIsLessOrEqualMaxUint() external givenBucketIsEnabled(0) {
        // it should decrease the bucket's totalDeposits by the given amount
        // it should not affect other buckets
        twlBaseMock.supplyInBucket(10 ether, 0);
        assertEq(twlBaseMock.getBucket(0).totalDeposits, 10 ether);
        assertEq(twlBaseMock.getBucket(1).totalDeposits, 0 ether);

        twlBaseMock.supplyInBucket(type(uint256).max - 10 ether, 0);
        assertEq(twlBaseMock.getBucket(0).totalDeposits, type(uint256).max);
        assertEq(twlBaseMock.getBucket(1).totalDeposits, 0 ether);
    }

    function test_RevertWhen_AmountIsGreaterThanMaxUint() external givenBucketIsEnabled(0) {
        // it should revert
        vm.expectRevert(stdError.arithmeticError);
        twlBaseMock.supplyInBucket(type(uint256).max + 1, 0);
    }

    function test_RevertGiven_BucketIsDisabled() external givenBucketIsDisabled(0) {
        // it should revert
        vm.expectRevert(ITWLBase.BUCKET_DISABLED.selector);
        twlBaseMock.supplyInBucket(10 ether, 0);
    }
}
