// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBorrowCallback {
    /// @notice Callback function for borrowing
    /// @param assets the amount of assets to borrow - "in" amount for the swap
    /// @param onBehalf the address of the user whose position is being borrowed
    /// @param swapParams ABI-encoded swap parameter (see `SwapParams` struct for details)
    /// @dev Called during market's `borrow`
    function onBorrowCallback(uint256 assets, address onBehalf, bytes calldata swapParams) external;
}

interface IRemoveCollateralCallback {
    /// @notice Callback function for removing collateral
    /// @param assets the amount of assets to remove - "in" amount for the swap
    /// @param onBehalf the address of the user whose collateral is being removed
    /// @param swapParams ABI-encoded swap parameter (see `SwapParams` struct for details)
    /// @dev Called during market's `removeCollateral`
    function onRemoveCollateralCallback(uint256 assets, address onBehalf, bytes calldata swapParams) external;
}

/// @notice Callback interface for liquidator to call during liquidation
interface ILiquidateCallback {
    /// @notice Callback function for liquidator to call during liquidation
    /// @param assetsToRepay The amount of token to be repaid by the callback receiver, this will be amount of borrow token of market
    /// @dev The callback receiver needs to give approval of assetsToRepay of borrow token of market to the market
    /// @param collateralReceived The amount of collateral received by the liquidator receiving the callback
    /// @dev The callback receiver needs to give approval of collateralReceived of collateral token of market to the market
    /// @param data Additional data for the liquidation
    function onLiquidateCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data) external;
}
