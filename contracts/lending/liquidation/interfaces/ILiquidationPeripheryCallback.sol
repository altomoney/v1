// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Callback interface for LiquidationPeriphery to call during liquidation
interface ILiquidationPeripheryCallback {
    /// @notice Callback function for LiquidationPeriphery to call during liquidation
    /// @param assetsToRepay The amount of token to be repaid by the callback receiver, this will be amount of underlying asset of USM
    /// @dev The callback receiver needs to give approval of assetsToRepay of underlying asset of USM to the LiquidationPeriphery
    /// @param collateralReceived The amount of collateral received by the liquidator receiving the callback
    /// @param data Additional data for the liquidation needed by the liquidator receiving the callback
    function onLiquidationPeripheryCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data)
        external;
}
