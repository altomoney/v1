// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/// @title Curve StableSwap NG Factory Interface
/// @notice Factory registry surface used to validate a StableSwap NG pool.
interface ICurveStableSwapNGFactory {
    /// @notice Returns the number of coins registered for `pool`.
    function get_n_coins(address pool) external view returns (uint256 coinCount);

    /// @notice Returns the coins registered for `pool`, in pool order.
    function get_coins(address pool) external view returns (address[] memory coins);

    /// @notice Returns the implementation registered for `pool`.
    function get_implementation_address(address pool) external view returns (address implementation);

    /// @notice Returns whether `pool` is registered as a metapool.
    function is_meta(address pool) external view returns (bool isMetapool);

    /// @notice Returns the Curve asset type registered for each pool coin.
    function get_pool_asset_types(address pool) external view returns (uint8[] memory assetTypes);
}
