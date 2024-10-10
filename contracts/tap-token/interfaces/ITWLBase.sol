// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

struct Bucket {
    bool enabled; // If the bucket is enabled or disabled
    uint24 epochGrowthRate; // Epoch growth if total deposits are increasing versus previous epoch
    uint24 epochDecayRate; // Epoch decay if total deposits are decreasing versus previous epoch
    uint24 epochCeiling; // Maximum epoch limit
    uint24 epochFloor; // Minimum epoch limit
    uint16 rewardsMultiplier; // Multiplier %, max 1e4
    uint16 growthBufferPercent; // uffer % to grow or decay lockEpochDuration, max 1e4
    uint24 lockEpochDuration; // Current bucket lock epoch
    uint256 totalDepositsLastEpoch;
    uint256 totalDeposits;
}

interface ITWLBase {
    error MAX_BUCKETS_REACHED();
    error BUCKET_DISABLED();
    error BUCKET_REWARDS_MULTIPLIER_MAX_REACHED();
    error BUCKET_GROWTH_BUFFER_PERCENT_MAX_REACHED();
    error BUCKET_FLOOR_CEILING_MISMATCH();
    error EPOCH_NOT_FINISHED();
    error EPOCH_DURATION_ZERO();
    error SafeCastOverflowedUintDowncast(uint256 uintType, uint256 amount);
    error BUCKET_EPOCH_DURATION_CEILING_MISMATCH();
    error BUCKET_EPOCH_DURATION_FLOOR_MISMATCH();

    event AdvanceEpoch(uint256 indexed newEpoch, uint256 lastEpoch);
    event BucketUpdated(uint256 indexed index);

    /**
     * @notice Returns the current epoch number
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Add a new bucket
     * @param bucket Bucket to add into the system
     */
    function addBucket(Bucket memory bucket) external;

    /**
     * @notice Updates an existing bucket
     * @param index Index of the bucket to update
     * @param bucket Bucket to add into the system
     * @dev Ignores the lockEpochDuration field.
     */
    function updateBucket(uint8 index, Bucket memory bucket) external;

    /**
     * @notice Return bucket at a specific index
     */
    function getBucket(uint8 index) external view returns (Bucket memory);

    /**
     * @notice Return a list of buckets
     */
    function getBuckets() external view returns (Bucket[] memory);
}
