// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Callback interface for liquidator to call during liquidation from periphery
/// @notice This callback is mainly used by liquidator to perform capital free liquidations
/// @dev the collateral seized from liquidation would have been transferred to liquidator before making this callback
/// @dev The callback contract can swap collateral to borrow token or stable token in USM to repay the borrow amount based on repayViaUsm flag
interface ILiquidationPeripheryCallback {
    /// @notice Callback function for liquidator to call during liquidation
    /// @notice The implementor of callback should do proper validation on the caller before giving approvals
    /// @param collateralReceived The amount of collateral received by the liquidator
    /// @param assetToSend The asset to give approval to the periphery contract
    /// @param assetAmountToSend The amount of asset to give approval to the periphery contract
    /// @param liquidationPeripheryCallbackData Additional data to passed to the callback receiver of liquidation periphery contract
    function onLiquidationPeripheryCallback(
        uint256 collateralReceived,
        address assetToSend,
        uint256 assetAmountToSend,
        bytes calldata liquidationPeripheryCallbackData
    ) external;
}
