// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IUsmCommon
/// @notice Shared enums, constants, and types used across both USM implementation lineages
///         (`Usm` and `AdvancedPermissionsUsm`).

/// @notice Identifies which USM implementation lineage a deployment uses.
/// @dev STANDARD - `Usm` base (e.g. `DUSDUsm`): unified `AccessMode` via `SWAPPER_ROLE`.
/// @dev ADVANCED_PERMISSIONS - `AdvancedPermissionsUsm` base (e.g. `DUSDAdvancedPermissionsUsm`): independent
///      per-direction `DirectionAccess` and fee tiers.
enum UsmType {
    STANDARD,
    ADVANCED_PERMISSIONS
}
