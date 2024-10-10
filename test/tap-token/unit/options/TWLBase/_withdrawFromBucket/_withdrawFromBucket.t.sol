// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TWLBaseMock, Bucket} from "test/tap-token/mocks/TWLBaseMock.sol";
import {ITWLBase} from "tap-token/interfaces/ITWLBase.sol";
import {stdError} from "forge-std/StdError.sol";

contract TWLBase_withdrawFromBucket is Test {
    TWLBaseMock twlBaseMock;

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

    function setUp() external {
        Bucket[] memory buckets = new Bucket[](2);
        buckets[0] = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);
        buckets[1] = Bucket(true, 2, 1, 1, 1, 1, 1, 1, 1, 1);

        twlBaseMock = new TWLBaseMock(7 days, buckets);

        twlBaseMock.supplyInBucket(10 ether, 0);
        twlBaseMock.supplyInBucket(10 ether, 1);
    }

    function test_WhenAmountIsLessThanOrEqualToBucketsTotalDeposits() external givenBucketIsEnabled(1) {
        // it should decrease the bucket's totalDeposits by the given amount
        // it should not affect other buckets
        twlBaseMock.withdrawFromBucket(5 ether, 1);
        assertEq(twlBaseMock.getBucket(1).totalDeposits, 5 ether);
        assertEq(twlBaseMock.getBucket(0).totalDeposits, 10 ether);

        twlBaseMock.withdrawFromBucket(5 ether, 1);
        assertEq(twlBaseMock.getBucket(1).totalDeposits, 0 ether);
        assertEq(twlBaseMock.getBucket(0).totalDeposits, 10 ether);
    }

    function test_RevertWhen_AmountIsGreaterThanBucketsTotalDeposits() external givenBucketIsEnabled(0) {
        // it should revert
        vm.expectRevert(stdError.arithmeticError);
        twlBaseMock.withdrawFromBucket(10 ether + 1, 0);
    }

    function test_RevertGiven_BucketIsDisabled() external givenBucketIsDisabled(0) {
        // it should revert
        vm.expectRevert(ITWLBase.BUCKET_DISABLED.selector);
        twlBaseMock.withdrawFromBucket(10 ether, 0);
    }
}
