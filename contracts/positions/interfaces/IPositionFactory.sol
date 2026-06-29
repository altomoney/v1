// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PositionType} from "./IPosition.sol";

/// @notice Config for MintCurveConvexPosition strategy
struct MintCurveConvexConfig {
    /// @notice address of frxUSD token
    address frxUsd;
    /// @notice address of curve pool containing frxUSD and DUSD as underlying tokens
    address curvePool;
    /// @notice address of convex booster contract
    address convexBooster;
    /// @notice address of convex reward pool contract where convex lp tokens are staked
    address convexRewardPool;
    /// @notice id of the curve pool to stake curve lp tokens in convex
    uint256 convexPid;
    /// @notice address of CRV token (Curve reward token)
    address crv;
    /// @notice address of CVX token (Convex reward token)
    address cvx;
}

interface IPositionFactoryErrors {
    /// @notice Thrown when the requested position type is not configured.
    error PositionFactoryUnsupportedType();

    /// @notice Thrown when a required address is zero.
    error PositionFactoryZeroAddress();

    /// @notice Thrown when factory or beacon configuration is invalid.
    error PositionFactoryInvalidConfig();

    /// @notice Thrown when a beacon is already set for a strategy type.
    error PositionFactoryBeaconAlreadySet();

    /// @notice Thrown when the market is not supported.
    error PositionFactoryUnsupportedMarket();
}

interface IPositionFactoryEvents {
    /// @notice Emitted when a new position proxy is deployed.
    event PositionCreated(address indexed owner, address indexed position, PositionType indexed positionType);

    /// @notice Emitted when the beacon for a strategy type is registered or updated.
    event BeaconSet(PositionType indexed positionType, address indexed beacon);

    /// @notice Emitted when the shared Curve / Convex configuration is updated.
    event MintCurveConvexConfigSet(MintCurveConvexConfig config);

    /// @notice Emitted when a swap target approval is changed.
    event ApprovedSwapTargetSet(address indexed swapTarget, bool approved);

    /// @notice Emitted when a registered beacon implementation is upgraded.
    event BeaconImplementationUpgraded(PositionType indexed positionType, address indexed implementation);

    /// @notice Emitted when the market registry is set.
    event MarketRegistrySet(address indexed marketRegistry);
}

interface IPositionFactoryBase is IPositionFactoryErrors, IPositionFactoryEvents {
    /// @notice Returns the beacon used for a strategy type.
    function beacon(PositionType positionType) external view returns (address);

    /// @notice Returns the market registry used to validate mint markets.
    function marketRegistry() external view returns (address);

    /// @notice Returns whether a swap target is currently approved by the factory.
    function approvedSwapTarget(address swapTarget) external view returns (bool);

    /// @notice Registers the beacon used for a strategy type.
    /// @param positionType The strategy type whose beacon is being set.
    /// @param _beacon The beacon address for the strategy type.
    /// @dev Setting beacon of position type which is already set will revert
    ///      The reason is if some position is already deployed with same position type,
    ///      there will be two different implementation of same position type(i.e. one from old beacon and one from new beacon)
    function setBeacon(PositionType positionType, address _beacon) external;

    /// @notice Sets the market registry used to validate mint markets.
    /// @param _marketRegistry The address of the market registry.
    function setMarketRegistry(address _marketRegistry) external;

    /// @notice Sets the mint market / Curve / Convex pool configuration read by all positions.
    /// @param config The strategy configuration to store in the factory.
    function setMintCurveConvexConfig(MintCurveConvexConfig calldata config) external;

    /// @notice Approves or revokes a swap target for all positions reading from this factory.
    /// @param swapTarget The swap target whose approval status is being updated.
    /// @param approved Whether the swap target is approved.
    function setApprovedSwapTarget(address swapTarget, bool approved) external;

    /// @notice Deploys a position for the caller using the current factory config.
    /// @param positionType The type of position to create.
    /// @param data ABI-encoded strategy-specific constructor data.
    /// @return position The address of the deployed position proxy.
    function createPosition(PositionType positionType, bytes calldata data) external returns (address position);
}

interface IPositionFactoryStaticTypes is IPositionFactoryBase {
    /// @notice Returns the current MintCurveConvexPosition strategy configuration.
    function mintCurveConvexConfig()
        external
        view
        returns (
            address frxUsd,
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        );
}

interface IPositionFactory is IPositionFactoryBase {
    /// @notice Returns the current MintCurveConvexPosition strategy configuration.
    function mintCurveConvexConfig() external view returns (MintCurveConvexConfig memory);
}
