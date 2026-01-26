// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title ISyrupAsset
/// @notice Interface for Syrup assets that support exit asset conversion
interface ISyrupAsset {
    /// @notice Converts a given amount of shares to the equivalent exit assets
    /// @param shares The amount of shares to convert
    /// @return assets The equivalent amount of exit assets
    function convertToExitAssets(uint256 shares) external view returns (uint256 assets);
}
