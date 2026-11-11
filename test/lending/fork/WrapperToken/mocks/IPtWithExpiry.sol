// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/// @notice Minimal Pendle PT interface used by expiry-based oracle mocks.
interface IPtWithExpiry {
    /// @notice Returns the PT maturity timestamp.
    function expiry() external view returns (uint256);
}
