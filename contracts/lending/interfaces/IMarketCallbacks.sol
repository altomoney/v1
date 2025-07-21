// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBorrowCallback {
    function onBorrowCallback(uint256 assets, address onBehalf, bytes calldata data) external;
}

interface IRemoveCollateralCallback {
    function onRemoveCollateralCallback(uint256 assets, address onBehalf, bytes calldata data) external;
}

/// @notice Callback interface for liquidator to call during liquidation
interface ILiquidateCallback {
    /// @notice Callback function for liquidator to call during liquidation
    /// @param assets The amount of borrow token to be repaid by the liquidator
    /// @param data Additional data for the liquidation
    function onLiquidateCallback(uint256 assets, bytes calldata data) external;
}
