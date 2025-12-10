// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IStableTokenFacilitator
 * @author GPM
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Defines the behavior of a Stable Token Facilitator
 */
interface IStableTokenFacilitator {
    /**
     * @dev Emitted when fees are distributed to the fee recipient
     * @param feeRecipient The address of the Fee Recipient
     * @param asset The address of the asset transferred to the fee recipient
     * @param amount The amount of the asset transferred to the Fee Recipient
     */
    event FeesDistributedToFeeRecipient(address indexed feeRecipient, address indexed asset, uint256 amount);

    /**
     * @dev Emitted when Stable Token Fee Recipient address is updated
     * @param oldStableTokenFeeRecipient The address of the old Stable Token Fee Recipient contract
     * @param newStableTokenFeeRecipient The address of the new Stable Token Fee Recipient contract
     */
    event StableTokenFeeRecipientUpdated(
        address indexed oldStableTokenFeeRecipient, address indexed newStableTokenFeeRecipient
    );

    /**
     * @notice Distribute fees to the Fee Recipient
     */
    function distributeFeesToFeeRecipient() external;

    /**
     * @notice Updates the address of the Stable Token Fee Recipient
     * @param newStableTokenFeeRecipient The address of the new Stable Token Fee Recipient
     */
    function updateFeeRecipient(address newStableTokenFeeRecipient) external;

    /**
     * @notice Returns the address of the Stable Token Fee Recipient
     * @return The address of the Stable Token Fee Recipient contract
     */
    function getFeeRecipient() external view returns (address);
}
