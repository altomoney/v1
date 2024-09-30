// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ITWLBase} from "../interfaces/ITWLBase.sol";

/**
 * @title TWLBase
 * @dev The TWLBase contract is a base contract for managing Time Weighted Locks with different buckets/presets, each one with a locking epoch duration that grows or decays depending on the supply momentum.
 */
abstract contract TWLBase is ITWLBase {
    uint256 public immutable EPOCH_DURATION;
    uint256 public immutable INIT_TIMESTAMP;
    uint256 public totalDeposits;
    uint256 public totalDepositsLastEpoch;
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
        if (lastEpoch == currentWeek()) {
            revert EPOCH_NOT_FINISHED();
        }

        for (uint256 i = 0; i < buckets.length; i++) {
            Bucket storage bucket = buckets[i];
            if (totalDeposits >= totalDepositsLastEpoch) {
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
        }

        totalDepositsLastEpoch = totalDeposits;
        lastEpoch = currentWeek();
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

        buckets.push(bucket);

        emit BucketUpdated(buckets.length - 1);
    }

    /**
     * @dev Updates bucket params at a specific index.
     */
    function _updateBucket(uint8 index, Bucket memory bucket) internal {
        if (bucket.rewardsMultiplier > 1e6) {
            revert BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
        }
        if (bucket.epochFloor > bucket.epochCeiling) {
            revert BUCKET_FLOOR_CEILING_MISMATCH();
        }
        bucket.lockEpochDuration = buckets[index].lockEpochDuration;

        buckets[index] = bucket;

        emit BucketUpdated(index);
    }

    function currentWeek() public view returns (uint256) {
        return (block.timestamp - INIT_TIMESTAMP) / EPOCH_DURATION;
    }

    /**
     * @notice Add a new bucket
     */
    function addBucket(Bucket memory bucket) external virtual;

    /**
     * @notice Updates an existing bucket
     * @dev Ignores the lockEpochDuration field.
     */
    function updateBucket(uint8 index, Bucket memory bucket) external virtual;
}
