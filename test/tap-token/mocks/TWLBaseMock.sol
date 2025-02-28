// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TWLBase, Bucket} from "tap-token/governance/TWLBase.sol";

/// @dev Mock contract for testing TWLBase abstract contract functions
contract TWLBaseMock is TWLBase {
    constructor(uint256 epochDuration, Bucket[] memory buckets) TWLBase(epochDuration, buckets) {}

    function addBucket(Bucket memory bucket) external override {
        _addBucket(bucket);
    }

    function updateBucket(uint8 index, Bucket memory bucket) external override {
        _updateBucket(index, bucket);
    }

    function supplyInBucket(uint256 amount, uint8 index) external {
        _supplyInBucket(index, amount);
    }

    function syncTWLBuckets(uint256 epochs) external {
        _syncTWLBuckets(epochs);
    }
}
