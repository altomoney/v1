// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IVaultRegistry} from "./interfaces/IVaultRegistry.sol";

/// @title VaultRegistry
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Main registry of vault contracts
contract VaultRegistry is AltoOwnable2Step, IVaultRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Set of vault addresses
    EnumerableSet.AddressSet private _vaultList;

    /// @notice Constructor
    /// @param owner The address of the contract owner
    constructor(address owner) Ownable(owner) {}

    /// @inheritdoc IVaultRegistry
    function addVault(address vault) external onlyOwner {
        if (vault == address(0)) revert VaultRegistryZeroAddress();
        if (!_vaultList.add(vault)) revert VaultRegistryVaultAlreadyExists();
        emit VaultAdded(vault);
    }

    /// @inheritdoc IVaultRegistry
    function removeVault(address vault) external onlyOwner {
        if (vault == address(0)) revert VaultRegistryZeroAddress();
        if (!_vaultList.remove(vault)) revert VaultRegistryVaultDoesNotExist();
        emit VaultRemoved(vault);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultList() external view returns (address[] memory) {
        return _vaultList.values();
    }

    /// @inheritdoc IVaultRegistry
    function getVaultListLength() external view returns (uint256) {
        return _vaultList.length();
    }

    /// @inheritdoc IVaultRegistry
    function getVaultAtIndex(uint256 index) external view returns (address) {
        if (index >= _vaultList.length()) revert VaultRegistryInvalidIndex();
        return _vaultList.at(index);
    }

    /// @inheritdoc IVaultRegistry
    function isVault(address vault) external view returns (bool) {
        return _vaultList.contains(vault);
    }
}
