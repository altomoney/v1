// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Shared configuration for MintCurveConvexPosition instances.
struct MintCurveConvexConfig {
    /// @notice Curve pool holding DUSD (and one other stable token) as underlying tokens.
    address curvePool;
    /// @notice Convex booster contract used to stake Curve LP.
    address convexBooster;
    /// @notice Convex reward pool where staked LP and rewards are tracked.
    address convexRewardPool;
    /// @notice Convex pool id used when staking the Curve LP.
    uint256 convexPid;
    /// @notice CRV(Curve token) reward token.
    address crv;
    /// @notice CVX(Convex token) reward token.
    address cvx;
}

interface IMintCurveConvexPositionFactoryErrors {
    /// @notice Thrown when a required address is zero.
    error MintCurveConvexPositionFactoryZeroAddress();

    /// @notice Thrown when the strategy configuration is invalid.
    error MintCurveConvexPositionFactoryInvalidConfig();

    /// @notice Thrown when the beacon is already set.
    error MintCurveConvexPositionFactoryBeaconAlreadySet();

    /// @notice Thrown when creating a position before the beacon is set.
    error MintCurveConvexPositionFactoryBeaconNotSet();

    /// @notice Thrown when the market is not a supported mint market.
    error MintCurveConvexPositionFactoryUnsupportedMarket();
}

interface IMintCurveConvexPositionFactoryEvents {
    /// @notice Emitted when a new position proxy is deployed.
    event PositionCreated(address indexed owner, address indexed position);

    /// @notice Emitted when the position beacon is set.
    event BeaconSet(address indexed beacon);

    /// @notice Emitted when the config of MintCurveConvexPosition is set.
    event MintCurveConvexConfigSet(MintCurveConvexConfig config);

    /// @notice Emitted when the market registry is set.
    event MarketRegistrySet(address indexed marketRegistry);
}

interface IMintCurveConvexPositionFactoryBase is
    IMintCurveConvexPositionFactoryErrors,
    IMintCurveConvexPositionFactoryEvents
{
    /// @notice Beacon whose implementation is used for all deployed positions
    /// @return Beacon address
    function beacon() external view returns (address);

    /// @notice returns the market registry used to validate mint markets
    function marketRegistry() external view returns (address);

    /// @notice Sets the position beacon for MintCurveConvex strategy.
    /// @dev This can only be set once because if it's updated, there can be positions with
    ///      different implementations based on beacon during it's deployment.
    /// @dev The beacon to set will be PositionBeacon whose implementation is MintCurveConvexPosition.
    /// @param beacon The beacon address.
    function setBeacon(address beacon) external;

    /// @notice Sets the market registry used to validate mint markets.
    /// @param marketRegistry The market registry address.
    function setMarketRegistry(address marketRegistry) external;

    /// @notice Deploys a position for the caller tied to a given mint market.
    /// @param market The mint market the position will use.
    /// @return position The deployed position proxy address.
    function createPosition(address market) external returns (address position);
}

interface IMintCurveConvexPositionFactoryStaticTypes is IMintCurveConvexPositionFactoryBase {
    /// @notice Returns the current Curve/Convex configuration
    /// @return curvePool The address of the Curve pool holding DUSD (and one other stable token) as underlying tokens.
    /// @return convexBooster The address of the Convex booster contract used to stake Curve LP.
    /// @return convexRewardPool The address of the Convex reward pool where staked LP and rewards are tracked.
    /// @return convexPid The Convex pool id used when staking the Curve LP.
    /// @return crv The address of the CRV(Curve token) reward token.
    /// @return cvx The address of the CVX(Convex token) reward token.
    function config()
        external
        view
        returns (
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        );
}

interface IMintCurveConvexPositionFactory is IMintCurveConvexPositionFactoryBase {
    /// @notice Returns the current Curve/Convex configuration
    /// @return config The configuration struct
    function config() external view returns (MintCurveConvexConfig memory);
}
