// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface ITWLBase {
    struct Bucket {
        bool enabled; // If the bucket is enabled or disabled
        uint24 epochGrowthRate; // Epoch growth if total deposits are increasing versus previous epoch
        uint24 epochDecayRate; // Epoch decay if total deposits are decreasing versus previous epoch
        uint24 epochCeiling; // Maximum epoch limit
        uint24 epochFloor; // Minimum epoch limit
        uint24 rewardsMultiplier; // Multiplier %, max 100 * 1e4
        uint128 lockEpochDuration; // Current bucket lock epoch
    }

    error MAX_BUCKETS_REACHED();
    error BUCKET_DISABLED();
    error BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
    error BUCKET_FLOOR_CEILING_MISMATCH();
    error EPOCH_NOT_FINISHED();

    event AdvanceEpoch(uint256 indexed newEpoch, uint256 lastEpoch);
    event BucketUpdated(uint256 indexed index);
}
