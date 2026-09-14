// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IUsmRegistry} from "./interfaces/IUsmRegistry.sol";
import {UsmType} from "@alto/usm/interfaces/IUsmCommon.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

/// @title UsmRegistry
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Main registry of USM (Universal Stability Module) contracts
contract UsmRegistry is AltoOwnable2Step, IUsmRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Set of USM addresses
    EnumerableSet.AddressSet private _usmList;

    /// @notice Constructor
    /// @param owner The address of the contract owner
    constructor(address owner) Ownable(owner) {
        if (owner == address(0)) revert UsmRegistryZeroAddress();
    }

    /// @inheritdoc IUsmRegistry
    function addUsm(address usm) external onlyOwner {
        if (usm == address(0)) revert UsmRegistryZeroAddress();
        if (!_usmList.add(usm)) revert UsmRegistryUsmAlreadyExists();
        emit UsmAdded(usm);
    }

    /// @inheritdoc IUsmRegistry
    function removeUsm(address usm) external onlyOwner {
        if (usm == address(0)) revert UsmRegistryZeroAddress();
        if (!_usmList.remove(usm)) revert UsmRegistryUsmDoesNotExist();
        emit UsmRemoved(usm);
    }

    /// @inheritdoc IUsmRegistry
    function getUsmList() external view returns (address[] memory) {
        return _usmList.values();
    }

    /// @inheritdoc IUsmRegistry
    function getUsmList(UsmType usmType) external view returns (address[] memory) {
        uint256 length = _usmList.length();
        address[] memory allUsms = _usmList.values();

        uint256 count;
        for (uint256 i = 0; i < length; ++i) {
            if (IUsm(allUsms[i]).USM_TYPE() == usmType) {
                ++count;
            }
        }

        address[] memory filteredUsms = new address[](count);
        uint256 index;
        for (uint256 i = 0; i < length; ++i) {
            if (IUsm(allUsms[i]).USM_TYPE() == usmType) {
                filteredUsms[index] = allUsms[i];
                ++index;
            }
        }

        return filteredUsms;
    }

    /// @inheritdoc IUsmRegistry
    function getUsmListLength() external view returns (uint256) {
        return _usmList.length();
    }

    /// @inheritdoc IUsmRegistry
    function getUsmAtIndex(uint256 index) external view returns (address) {
        if (index >= _usmList.length()) revert UsmRegistryInvalidIndex();
        return _usmList.at(index);
    }

    /// @inheritdoc IUsmRegistry
    function isUsm(address usm) external view returns (bool) {
        return _usmList.contains(usm);
    }
}

