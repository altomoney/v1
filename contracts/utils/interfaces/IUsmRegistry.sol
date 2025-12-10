// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IUsmRegistry
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for the UsmRegistry contract
interface IUsmRegistry {
    /// @notice Error thrown when the address is zero
    error UsmRegistryZeroAddress();

    /// @notice Error thrown when the USM already exists
    error UsmRegistryUsmAlreadyExists();

    /// @notice Error thrown when the USM does not exist
    error UsmRegistryUsmDoesNotExist();

    /// @notice Error thrown when the index is invalid
    error UsmRegistryInvalidIndex();

    /// @notice Emitted when a USM is added
    /// @param usm The address of the USM
    event UsmAdded(address indexed usm);

    /// @notice Emitted when a USM is removed
    /// @param usm The address of the USM
    event UsmRemoved(address indexed usm);

    /// @notice Adds a USM to the registry
    /// @param usm The address of the USM to add
    function addUsm(address usm) external;

    /// @notice Removes a USM from the registry
    /// @param usm The address of the USM to remove
    function removeUsm(address usm) external;

    /// @notice Returns the list of all USMs
    /// @return Array of USM addresses
    function getUsmList() external view returns (address[] memory);

    /// @notice Returns the number of USMs
    /// @return The number of USMs
    function getUsmListLength() external view returns (uint256);

    /// @notice Returns the USM at the given index
    /// @param index The index of the USM
    /// @return The address of the USM
    function getUsmAtIndex(uint256 index) external view returns (address);

    /// @notice Checks if an address is a registered USM
    /// @param usm The address to check
    /// @return True if the address is a registered USM
    function isUsm(address usm) external view returns (bool);
}

