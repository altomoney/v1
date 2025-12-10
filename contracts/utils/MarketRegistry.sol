// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMarketRegistry} from "./interfaces/IMarketRegistry.sol";

/// @title MarketRegistry
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Main registry of mint and borrow market contracts
contract MarketRegistry is AltoOwnable2Step, IMarketRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Set of mint market addresses
    EnumerableSet.AddressSet private _mintMarkets;

    /// @dev Set of borrow market addresses
    EnumerableSet.AddressSet private _borrowMarkets;

    /// @notice Constructor
    /// @param owner The address of the contract owner
    constructor(address owner) Ownable(owner) {
        if (owner == address(0)) revert MarketRegistryZeroAddress();
    }

    /// @inheritdoc IMarketRegistry
    function addMintMarket(address market) external onlyOwner {
        if (market == address(0)) revert MarketRegistryZeroAddress();
        if (!_mintMarkets.add(market)) revert MarketRegistryMarketAlreadyExists();
        emit MintMarketAdded(market);
    }

    /// @inheritdoc IMarketRegistry
    function removeMintMarket(address market) external onlyOwner {
        if (market == address(0)) revert MarketRegistryZeroAddress();
        if (!_mintMarkets.remove(market)) revert MarketRegistryMarketDoesNotExist();
        emit MintMarketRemoved(market);
    }

    /// @inheritdoc IMarketRegistry
    function addBorrowMarket(address market) external onlyOwner {
        if (market == address(0)) revert MarketRegistryZeroAddress();
        if (!_borrowMarkets.add(market)) revert MarketRegistryMarketAlreadyExists();
        emit BorrowMarketAdded(market);
    }

    /// @inheritdoc IMarketRegistry
    function removeBorrowMarket(address market) external onlyOwner {
        if (market == address(0)) revert MarketRegistryZeroAddress();
        if (!_borrowMarkets.remove(market)) revert MarketRegistryMarketDoesNotExist();
        emit BorrowMarketRemoved(market);
    }

    /// @inheritdoc IMarketRegistry
    function getMintMarkets() external view returns (address[] memory) {
        return _mintMarkets.values();
    }

    /// @inheritdoc IMarketRegistry
    function getBorrowMarkets() external view returns (address[] memory) {
        return _borrowMarkets.values();
    }

    /// @inheritdoc IMarketRegistry
    function getMintMarketsLength() external view returns (uint256) {
        return _mintMarkets.length();
    }

    /// @inheritdoc IMarketRegistry
    function getBorrowMarketsLength() external view returns (uint256) {
        return _borrowMarkets.length();
    }

    /// @inheritdoc IMarketRegistry
    function getMintMarketAtIndex(uint256 index) external view returns (address) {
        if (index >= _mintMarkets.length()) revert MarketRegistryInvalidIndex();
        return _mintMarkets.at(index);
    }

    /// @inheritdoc IMarketRegistry
    function getBorrowMarketAtIndex(uint256 index) external view returns (address) {
        if (index >= _borrowMarkets.length()) revert MarketRegistryInvalidIndex();
        return _borrowMarkets.at(index);
    }

    /// @inheritdoc IMarketRegistry
    function isMintMarket(address market) external view returns (bool) {
        return _mintMarkets.contains(market);
    }

    /// @inheritdoc IMarketRegistry
    function isBorrowMarket(address market) external view returns (bool) {
        return _borrowMarkets.contains(market);
    }
}

