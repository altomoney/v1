// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IMarketRegistry
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for the MarketRegistry contract
interface IMarketRegistry {
    /// @notice Error thrown when the address is zero
    error MarketRegistryZeroAddress();

    /// @notice Error thrown when the market already exists
    error MarketRegistryMarketAlreadyExists();

    /// @notice Error thrown when the market does not exist
    error MarketRegistryMarketDoesNotExist();

    /// @notice Error thrown when the index is invalid
    error MarketRegistryInvalidIndex();

    /// @notice Emitted when a mint market is added
    /// @param market The address of the market
    event MintMarketAdded(address indexed market);

    /// @notice Emitted when a mint market is removed
    /// @param market The address of the market
    event MintMarketRemoved(address indexed market);

    /// @notice Emitted when a borrow market is added
    /// @param market The address of the market
    event BorrowMarketAdded(address indexed market);

    /// @notice Emitted when a borrow market is removed
    /// @param market The address of the market
    event BorrowMarketRemoved(address indexed market);

    /// @notice Adds a mint market to the registry
    /// @param market The address of the market to add
    function addMintMarket(address market) external;

    /// @notice Removes a mint market from the registry
    /// @param market The address of the market to remove
    function removeMintMarket(address market) external;

    /// @notice Adds a borrow market to the registry
    /// @param market The address of the market to add
    function addBorrowMarket(address market) external;

    /// @notice Removes a borrow market from the registry
    /// @param market The address of the market to remove
    function removeBorrowMarket(address market) external;

    /// @notice Returns the list of all mint markets
    /// @return Array of mint market addresses
    function getMintMarkets() external view returns (address[] memory);

    /// @notice Returns the list of all borrow markets
    /// @return Array of borrow market addresses
    function getBorrowMarkets() external view returns (address[] memory);

    /// @notice Returns the number of mint markets
    /// @return The number of mint markets
    function getMintMarketsLength() external view returns (uint256);

    /// @notice Returns the number of borrow markets
    /// @return The number of borrow markets
    function getBorrowMarketsLength() external view returns (uint256);

    /// @notice Returns the mint market at the given index
    /// @param index The index of the mint market
    /// @return The address of the mint market
    function getMintMarketAtIndex(uint256 index) external view returns (address);

    /// @notice Returns the borrow market at the given index
    /// @param index The index of the borrow market
    /// @return The address of the borrow market
    function getBorrowMarketAtIndex(uint256 index) external view returns (address);

    /// @notice Checks if a market is a mint market
    /// @param market The address of the market
    /// @return True if the market is a mint market
    function isMintMarket(address market) external view returns (bool);

    /// @notice Checks if a market is a borrow market
    /// @param market The address of the market
    /// @return True if the market is a borrow market
    function isBorrowMarket(address market) external view returns (bool);
}

