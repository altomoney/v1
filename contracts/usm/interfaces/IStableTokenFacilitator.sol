// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IStableTokenFacilitator
 * @author Pearl Labs
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Defines the behavior of a Stable Token Facilitator
 */
interface IStableTokenFacilitator {
    /**
     * @dev Emitted when fees are distributed to the Stable Token Treasury
     * @param stableTokenTreasury The address of the Stable Token Treasury
     * @param asset The address of the asset transferred to the Stable Token Treasury
     * @param amount The amount of the asset transferred to the Stable Token Treasury
     */
    event FeesDistributedToTreasury(address indexed stableTokenTreasury, address indexed asset, uint256 amount);

    /**
     * @dev Emitted when Stable Token Treasury address is updated
     * @param oldStableTokenTreasury The address of the old Stable Token Treasury contract
     * @param newStableTokenTreasury The address of the new Stable Token Treasury contract
     */
    event StableTokenTreasuryUpdated(address indexed oldStableTokenTreasury, address indexed newStableTokenTreasury);

    /**
     * @notice Distribute fees to the Stable Token Treasury
     */
    function distributeFeesToTreasury() external;

    /**
     * @notice Updates the address of the Stable Token Treasury
     * @dev WARNING: The Stable Token Treasury is where revenue fees are sent to. Update carefully
     * @param newStableTokenTreasury The address of the Stable Token Treasury
     */
    function updateStableTokenTreasury(address newStableTokenTreasury) external;

    /**
     * @notice Returns the address of the Stable Token Treasury
     * @return The address of the Stable Token Treasury contract
     */
    function getStableTokenTreasury() external view returns (address);
}
