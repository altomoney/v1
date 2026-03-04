// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IVaultRegistry
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for the VaultRegistry contract
interface IVaultRegistry {
    /// @notice Error thrown when the address is zero
    error VaultRegistryZeroAddress();

    /// @notice Error thrown when the vault already exists
    error VaultRegistryVaultAlreadyExists();

    /// @notice Error thrown when the vault does not exist
    error VaultRegistryVaultDoesNotExist();

    /// @notice Error thrown when the index is invalid
    error VaultRegistryInvalidIndex();

    /// @notice Emitted when a vault is added
    /// @param vault The address of the vault
    event VaultAdded(address indexed vault);

    /// @notice Emitted when a vault is removed
    /// @param vault The address of the vault
    event VaultRemoved(address indexed vault);

    /// @notice Adds a vault to the registry
    /// @param vault The address of the vault to add
    function addVault(address vault) external;

    /// @notice Removes a vault from the registry
    /// @param vault The address of the vault to remove
    function removeVault(address vault) external;

    /// @notice Returns the list of all vaults
    /// @return Array of vault addresses
    function getVaultList() external view returns (address[] memory);

    /// @notice Returns the number of vaults
    /// @return The number of vaults
    function getVaultListLength() external view returns (uint256);

    /// @notice Returns the vault at the given index
    /// @param index The index of the vault
    /// @return The address of the vault
    function getVaultAtIndex(uint256 index) external view returns (address);

    /// @notice Checks if an address is a registered vault
    /// @param vault The address to check
    /// @return True if the address is a registered vault
    function isVault(address vault) external view returns (bool);
}
