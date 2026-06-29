// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Strategy identifier returned by a position instance.
enum PositionType {
    MINT_CURVE_CONVEX
}

interface IPosition {
    /// @notice Strategy identifier for thw position instance.
    function positionType() external view returns (PositionType);

    /// @notice Implementation version of this position contract
    /// @dev This needs to be incremented when beacon implementation is upgraded
    function version() external view returns (uint256);

    /// @notice Extends the position.
    /// @param data ABI-encoded parameters for adding to the position
    function add(bytes calldata data) external;

    /// @notice Reduces or fully closes the position.
    /// @param data ABI-encoded parameters for reducing the position
    function remove(bytes calldata data) external;
}
