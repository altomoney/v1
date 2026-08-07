// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ICurveStableSwapFactory} from "@alto/oracles/dusd/interfaces/ICurveStableSwapFactory.sol";

/// @notice Stateful mock of the StableSwap NG factory registry reads used by
/// `DusdPegOracleCurve`.
/// @dev Metadata is stored per pool, matching the production factory's
/// `pool_data` model.
contract MockCurveStableSwapFactory is ICurveStableSwapFactory {
    error InvalidRegistration();

    uint256 private constant MIN_COINS = 2;
    uint256 private constant MAX_COINS = 8;
    address private constant MOCK_BASE_POOL = address(1);

    struct PoolData {
        uint256 nCoins;
        address[] coins;
        address basePool;
        uint8[] assetTypes;
        address implementation;
    }

    mapping(address pool => PoolData data) private s_poolData;

    /// @inheritdoc ICurveStableSwapFactory
    function get_n_coins(address pool) external view override returns (uint256 coinCount) {
        return s_poolData[pool].nCoins;
    }

    /// @inheritdoc ICurveStableSwapFactory
    function get_coins(address pool) external view override returns (address[] memory registeredCoins) {
        return s_poolData[pool].coins;
    }

    /// @inheritdoc ICurveStableSwapFactory
    function get_implementation_address(address pool) external view override returns (address implementation) {
        return s_poolData[pool].implementation;
    }

    /// @inheritdoc ICurveStableSwapFactory
    function is_meta(address pool) external view override returns (bool isMetapool) {
        return s_poolData[pool].basePool != address(0);
    }

    /// @inheritdoc ICurveStableSwapFactory
    function get_pool_asset_types(address pool) external view override returns (uint8[] memory assetTypes) {
        return s_poolData[pool].assetTypes;
    }

    /// @notice Registers all metadata used by the oracle for `pool`.
    function registerPool(
        address pool,
        address[] calldata coins,
        uint8[] calldata assetTypes,
        address implementation,
        bool isMetapool
    ) external {
        if (
            pool == address(0) || implementation == address(0) || coins.length < MIN_COINS || coins.length > MAX_COINS
                || assetTypes.length != coins.length
        ) {
            revert InvalidRegistration();
        }
        for (uint256 i; i < coins.length; ++i) {
            if (coins[i] == address(0)) revert InvalidRegistration();
            for (uint256 j = i + 1; j < coins.length; ++j) {
                if (coins[i] == coins[j]) revert InvalidRegistration();
            }
        }

        PoolData storage data = s_poolData[pool];
        data.nCoins = coins.length;
        _replaceCoins(data.coins, coins);
        data.basePool = isMetapool ? MOCK_BASE_POOL : address(0);
        _replaceAssetTypes(data.assetTypes, assetTypes);
        data.implementation = implementation;
    }

    function _replaceCoins(address[] storage storedCoins, address[] calldata coins) private {
        while (storedCoins.length != 0) {
            storedCoins.pop();
        }
        for (uint256 i; i < coins.length; ++i) {
            storedCoins.push(coins[i]);
        }
    }

    function _replaceAssetTypes(uint8[] storage storedAssetTypes, uint8[] calldata assetTypes) private {
        while (storedAssetTypes.length != 0) {
            storedAssetTypes.pop();
        }
        for (uint256 i; i < assetTypes.length; ++i) {
            storedAssetTypes.push(assetTypes[i]);
        }
    }
}
