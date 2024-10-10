// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ITWLBase, Bucket} from "../interfaces/ITWLBase.sol";

/**
 * @title TWLBase
 * @dev The TWLBase contract is a base contract for managing Time Weighted Locks with different buckets/presets, each one with a locking epoch duration that grows or decays depending on the supply momentum.
 */
abstract contract TWLBase is ITWLBase {
    uint256 public immutable EPOCH_DURATION;
    uint256 public immutable INIT_TIMESTAMP;
    uint256 public lastEpoch;

    Bucket[] public buckets;

    uint8 public constant MAX_BUCKETS = 255;

    constructor(uint256 _epochDuration, Bucket[] memory _buckets) {
        EPOCH_DURATION = _epochDuration;
        INIT_TIMESTAMP = block.timestamp;

        for (uint256 i = 0; i < _buckets.length; i++) {
            _addBucket(_buckets[i]);
        }
    }

    /**
     * @dev Update enabled buckets based on the total deposits in the contract.
     */
    function _syncTWLBuckets() internal {
        if (lastEpoch == currentEpoch()) {
            revert EPOCH_NOT_FINISHED();
        }

        for (uint256 i = 0; i < buckets.length; i++) {
            Bucket storage bucket = buckets[i];
            if (bucket.totalDeposits >= bucket.totalDepositsLastEpoch) {
                bucket.lockEpochDuration += bucket.epochGrowthRate;
            } else {
                bucket.lockEpochDuration -= bucket.epochDecayRate;
            }
            if (bucket.lockEpochDuration > bucket.epochCeiling) {
                bucket.lockEpochDuration = bucket.epochCeiling;
            }
            if (bucket.lockEpochDuration < bucket.epochFloor) {
                bucket.lockEpochDuration = bucket.epochFloor;
            }
            bucket.totalDepositsLastEpoch = bucket.totalDeposits;
        }

        lastEpoch = currentEpoch();
    }

    function _supplyInBucket(uint8 index, uint256 amount) internal {
        Bucket storage bucket = buckets[index];
        bucket.totalDeposits += amount;
    }

    function _withdrawFromBucket(uint8 index, uint256 amount) internal {
        Bucket storage bucket = buckets[index];
        bucket.totalDeposits -= amount;
    }

    function _addBucket(Bucket memory bucket) internal {
        if (buckets.length >= MAX_BUCKETS) {
            revert MAX_BUCKETS_REACHED();
        }
        if (bucket.rewardsMultiplier > 1e6) {
            revert BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
        }
        if (bucket.epochFloor > bucket.epochCeiling) {
            revert BUCKET_FLOOR_CEILING_MISMATCH();
        }

        bucket.totalDepositsLastEpoch = 0;
        bucket.totalDeposits = 0;

        buckets.push(bucket);

        emit BucketUpdated(buckets.length - 1);
    }

    /**
     * @dev Updates bucket params at a specific index.
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system, ignores lockEpochDuration, totalDepositsLastEpoch and totalDeposits fields
     */
    function _updateBucket(uint8 index, Bucket memory bucket) internal {
        if (bucket.rewardsMultiplier > 1e6) {
            revert BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
        }
        if (bucket.epochFloor > bucket.epochCeiling) {
            revert BUCKET_FLOOR_CEILING_MISMATCH();
        }
        // Replace input with current storage values for lockEpochDuration, totalDepositsLastEpoch and totalDeposits
        bucket.lockEpochDuration = buckets[index].lockEpochDuration;
        bucket.totalDepositsLastEpoch = buckets[index].totalDepositsLastEpoch;
        bucket.totalDeposits = buckets[index].totalDeposits;

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
