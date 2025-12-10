// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

/// @title AssetShareConversionMath
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Library for converting between asset amounts and share amounts with precision control.
library AssetShareConversionMath {
    using FixedPointMath for uint256;

    // Precision constants for share and asset calculations
    uint256 public constant VIRTUAL_SHARES = 1e6;
    uint256 public constant VIRTUAL_ASSETS = 1;

    /// @notice Converts assets to shares with ceiling rounding
    /// @param assetAmount The amount of assets to convert
    /// @param totalAssetSupply The total supply of assets
    /// @param totalShareSupply The total supply of shares
    /// @return The equivalent amount in shares, rounded up
    function convertToSharesUp(uint256 assetAmount, uint256 totalAssetSupply, uint256 totalShareSupply)
        internal
        pure
        returns (uint256)
    {
        return
            assetAmount.divideWithRounding(totalShareSupply + VIRTUAL_SHARES, totalAssetSupply + VIRTUAL_ASSETS, true);
    }

    /// @notice Converts assets to shares with floor rounding
    /// @param assetAmount The amount of assets to convert
    /// @param totalAssetSupply The total supply of assets
    /// @param totalShareSupply The total supply of shares
    /// @return The equivalent amount in shares, rounded down
    function convertToSharesDown(uint256 assetAmount, uint256 totalAssetSupply, uint256 totalShareSupply)
        internal
        pure
        returns (uint256)
    {
        return
            assetAmount.divideWithRounding(totalShareSupply + VIRTUAL_SHARES, totalAssetSupply + VIRTUAL_ASSETS, false);
    }

    /// @notice Converts shares to assets with ceiling rounding
    /// @param shareAmount The amount of shares to convert
    /// @param totalAssetSupply The total supply of assets
    /// @param totalShareSupply The total supply of shares
    /// @return The equivalent amount in assets, rounded up
    function convertToAssetsUp(uint256 shareAmount, uint256 totalAssetSupply, uint256 totalShareSupply)
        internal
        pure
        returns (uint256)
    {
        return
            shareAmount.divideWithRounding(totalAssetSupply + VIRTUAL_ASSETS, totalShareSupply + VIRTUAL_SHARES, true);
    }

    /// @notice Converts shares to assets with floor rounding
    /// @param shareAmount The amount of shares to convert
    /// @param totalAssetSupply The total supply of assets
    /// @param totalShareSupply The total supply of shares
    /// @return The equivalent amount in assets, rounded down
    function convertToAssetsDown(uint256 shareAmount, uint256 totalAssetSupply, uint256 totalShareSupply)
        internal
        pure
        returns (uint256)
    {
        return
            shareAmount.divideWithRounding(totalAssetSupply + VIRTUAL_ASSETS, totalShareSupply + VIRTUAL_SHARES, false);
    }
}
