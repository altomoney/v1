// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TWLBaseMock, Bucket} from "../TWLBaseMock.sol";

contract TWLBase_getBuckets is Test {
    TWLBaseMock twlBaseMock;

    function setUp() external {
        Bucket[] memory buckets = new Bucket[](0);
        twlBaseMock = new TWLBaseMock(7 days, buckets);
    }

    function test_GivenAnEmptyBucketsArray() external view {
        // it should return an empty array
        assertEq(twlBaseMock.getBuckets().length, 0);
    }

    function test_GivenANon_emptyBucketsArray() external {
        // it should return an array of all buckets
        Bucket memory bucketOne = Bucket(true, 1, 1, 1, 1, 1, 1, 1, 1, 1);
        Bucket memory bucketTwo = Bucket(true, 2, 1, 1, 1, 1, 1, 1, 1, 1);

        twlBaseMock.addBucket(bucketOne);

        assertEq(twlBaseMock.getBuckets().length, 1);

        twlBaseMock.addBucket(bucketTwo);

        assertEq(twlBaseMock.getBuckets().length, 2);

        assertEq(twlBaseMock.getBuckets()[0].epochGrowthRate, bucketOne.epochGrowthRate);
        assertEq(twlBaseMock.getBuckets()[1].epochGrowthRate, bucketTwo.epochGrowthRate);
    }
}
