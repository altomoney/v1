// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/// @title Curve StableSwap NG Factory Interface
///
/// @notice Minimal interface used to verify a pool's factory registration and
/// immutable metadata.
interface ICurveStableSwapFactory {
    /// @notice Returns the number of coins registered for `pool`.
    ///
    /// @param pool Pool to query.
    ///
    /// @return coinCount Number of registered coins.
    function get_n_coins(address pool) external view returns (uint256 coinCount);

    /// @notice Returns the coins registered for `pool`, in pool order.
    ///
    /// @param pool Pool to query.
    ///
    /// @return coins Registered coins in pool order.
    function get_coins(address pool) external view returns (address[] memory coins);

    /// @notice Returns the Curve implementation used by `pool`.
    ///
    /// @param pool Pool to query.
    ///
    /// @return implementation Registered pool implementation.
    function get_implementation_address(address pool) external view returns (address implementation);

    /// @notice Returns whether `pool` is a metapool.
    ///
    /// @param pool Pool to query.
    ///
    /// @return isMetapool Whether the pool is a metapool.
    function is_meta(address pool) external view returns (bool isMetapool);

    /// @notice Returns the Curve asset type registered for each coin in `pool`.
    ///
    /// @param pool Pool to query.
    ///
    /// @return assetTypes Asset-type identifiers in pool coin order.
    function get_pool_asset_types(address pool) external view returns (uint8[] memory assetTypes);
}
