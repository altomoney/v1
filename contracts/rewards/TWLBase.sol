// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ITWLBase, Bucket} from "./interfaces/ITWLBase.sol";
/**
 * @title TWLBase
 * @dev The TWLBase contract is a base contract for managing Time Weighted Locks with different buckets/presets, each one with a locking epoch duration that grows or decays depending on the supply momentum.
 */

abstract contract TWLBase is ITWLBase {
    uint256 public constant MAX_BUCKETS = 255;
    uint256 public immutable EPOCH_DURATION;
    uint256 public immutable INIT_TIMESTAMP;
    uint256 public lastEpoch;

    Bucket[] public buckets;

    constructor(uint256 epochDuration, Bucket[] memory initialBuckets) {
        if (epochDuration == 0) {
            revert EPOCH_DURATION_ZERO();
        }
        EPOCH_DURATION = epochDuration;
        INIT_TIMESTAMP = block.timestamp;

        for (uint256 i = 0; i < initialBuckets.length; i++) {
            _addBucket(initialBuckets[i]);
        }
    }

    /**
     * @dev Update enabled buckets based on the total deposits in the contract.
     */
    function _syncTWLBuckets(uint256 _limit) internal {
        if (_limit == 0) revert LIMIT_IS_ZERO();
        if (lastEpoch == currentEpoch()) {
            revert EPOCH_NOT_FINISHED();
        }

        uint256 lastWeek = lastEpoch;
        uint256 goal = currentEpoch();

        if (goal - lastWeek > _limit) {
            goal = lastWeek + _limit;
        }

        uint24 missingEpochs = uint24(goal - lastWeek);

        for (uint256 i; i < buckets.length; i++) {
            Bucket storage bucket = buckets[i];

            if (bucket.enabled == false) {
                continue;
            }

            if (bucket.currentEpochInflows >= (bucket.lastEpochInflows + (bucket.growthGoal * missingEpochs))) {
                bucket.lockEpochDuration += (bucket.epochGrowthRate * missingEpochs);
            } else {
                if (bucket.lockEpochDuration >= (bucket.epochDecayRate * missingEpochs)) {
                    bucket.lockEpochDuration -= (bucket.epochDecayRate * missingEpochs);
                } else {
                    bucket.lockEpochDuration = 0;
                }
            }
            if (bucket.lockEpochDuration > bucket.epochCeiling) {
                bucket.lockEpochDuration = bucket.epochCeiling;
            }
            if (bucket.lockEpochDuration < bucket.epochFloor) {
                bucket.lockEpochDuration = bucket.epochFloor;
            }
            bucket.lastEpochInflows = bucket.currentEpochInflows;
            bucket.currentEpochInflows = 0;
        }

        lastEpoch = goal;
    }

    function _supplyInBucket(uint8 index, uint256 amount) internal {
        if (buckets[index].enabled == false) revert BUCKET_DISABLED();

        Bucket storage bucket = buckets[index];
        bucket.currentEpochInflows += amount;
    }

    function _addBucket(Bucket memory bucket) internal {
        if (buckets.length >= MAX_BUCKETS) {
            revert MAX_BUCKETS_REACHED();
        }
        if (bucket.rewardsMultiplier > 1e4) {
            revert BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
        }
        if (bucket.epochFloor > bucket.epochCeiling) {
            revert BUCKET_FLOOR_CEILING_MISMATCH();
        }
        if (bucket.lockEpochDuration > bucket.epochCeiling) {
            revert BUCKET_EPOCH_DURATION_CEILING_MISMATCH();
        }
        if (bucket.lockEpochDuration < bucket.epochFloor) {
            revert BUCKET_EPOCH_DURATION_FLOOR_MISMATCH();
        }

        bucket.currentEpochInflows = 0;
        bucket.lastEpochInflows = 0;

        buckets.push(bucket);

        emit BucketUpdated(buckets.length - 1);
    }

    /**
     * @dev Updates bucket params at a specific index.
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system, ignores lockEpochDuration, totalDepositsLastEpoch and totalDeposits fields
     */
    function _updateBucket(uint8 index, Bucket memory bucket) internal {
        if (bucket.rewardsMultiplier > 1e4) {
            revert BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
        }
        if (bucket.epochFloor > bucket.epochCeiling) {
            revert BUCKET_FLOOR_CEILING_MISMATCH();
        }
        if (buckets[index].lockEpochDuration > bucket.epochCeiling) {
            revert BUCKET_EPOCH_DURATION_CEILING_MISMATCH();
        }
        if (buckets[index].lockEpochDuration < bucket.epochFloor) {
            revert BUCKET_EPOCH_DURATION_FLOOR_MISMATCH();
        }
        // Replace input with current storage values for lockEpochDuration and currentEpochInflows
        bucket.lockEpochDuration = buckets[index].lockEpochDuration;
        bucket.currentEpochInflows = buckets[index].currentEpochInflows;
        bucket.lastEpochInflows = buckets[index].lastEpochInflows;
        buckets[index] = bucket;

        emit BucketUpdated(index);
    }

    /**
     * @notice Returns the current epoch number
     */
    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - INIT_TIMESTAMP) / EPOCH_DURATION;
    }

    /**
     * @notice Add a new bucket
     * @param bucket Bucket to add into the system
     */
    function addBucket(Bucket memory bucket) external virtual;

    /**
     * @notice Updates an existing bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system
     * @dev Ignores the lockEpochDuration field.
     */
    function updateBucket(uint8 index, Bucket memory bucket) external virtual;

    /**
     * @notice Return bucket at a specific index
     */
    function getBucket(uint8 index) external view returns (Bucket memory) {
        return buckets[index];
    }

    /**
     * @notice Return a list of buckets
     */
    function getBuckets() external view returns (Bucket[] memory) {
        return buckets;
    }
}
