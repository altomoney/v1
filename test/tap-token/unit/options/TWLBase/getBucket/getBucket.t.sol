// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TWLBaseMock, Bucket} from "test/tap-token/mocks/TWLBaseMock.sol";

import {stdError} from "forge-std/StdError.sol";

contract TWLBase_getBucket is Test {
    TWLBaseMock twlBaseMock;
    Bucket[] buckets;

    function setUp() external {
        buckets.push(Bucket(true, 1, 1, 1, 1, 1, 1,1, 1, 1));
        twlBaseMock = new TWLBaseMock(7 days, buckets);
    }

    function test_GivenAValidBucketIndex() external view {
        // it should return the correct bucket
        assertEq(twlBaseMock.getBucket(0).enabled, buckets[0].enabled);
    }

    function test_RevertGiven_AnInvalidBucketIndex() external {
        // it should revert
        vm.expectRevert(stdError.indexOOBError);
        twlBaseMock.getBucket(1);
    }
}
