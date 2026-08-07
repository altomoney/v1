// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICurveStableSwapFactory} from "@alto/oracles/dusd/interfaces/ICurveStableSwapFactory.sol";
import {ICurveStableSwap} from "@alto/oracles/interfaces/ICurveStableSwap.sol";

/// @notice Immutable pool identity and controller-relevant parameters.
struct DusdPegOracleCurveConfig {
    /// @dev Address of the Curve StableSwap NG pool.
    address pool;
    /// @dev Expected implementation registered for `pool` by `factory`.
    address poolImpl;
    /// @dev Address of the Curve StableSwap NG factory that registered `pool`.
    address factory;
    /// @dev Address of DUSD, which must be coin 1.
    address dusd;
    /// @dev Address of the USD-par quote token, which must be coin 0.
    address quoteToken;
    /// @dev Required Curve EMA averaging time.
    uint256 maExpTime;
    /// @dev Required amplification coefficient, including Curve's precision factor.
    uint256 aPrecise;
}

/// @notice Unvalidated diagnostic snapshot of the underlying Curve pool.
/// @dev Values are returned directly from the pool and are not approved for
/// use by the PRM.
struct DusdPegOracleCurveRawPoolState {
    /// @dev Instantaneous AMM state price returned by `get_p(0)`.
    uint256 currentStatePriceWad;
    /// @dev Most recent AMM state price stored by Curve.
    uint256 lastStatePriceWad;
    /// @dev EMA value stored at Curve's most recent oracle update.
    uint256 storedEmaPriceWad;
    /// @dev EMA projected by Curve to the current block timestamp.
    uint256 currentEmaPriceWad;
    /// @dev Timestamp of Curve's most recent stored price update.
    uint256 priceUpdatedAt;
    /// @dev Timestamp of Curve's most recent stored invariant update.
    uint256 invariantUpdatedAt;
    /// @dev Pool's current EMA averaging time.
    uint256 maExpTime;
    /// @dev Pool's current amplification coefficient, including Curve's
    /// precision factor.
    uint256 aPrecise;
    /// @dev Pool's target amplification coefficient.
    uint256 futureAPrecise;
    /// @dev Current balance of coin 0, the quote token.
    uint256 quoteTokenBalance;
    /// @dev Current balance of coin 1, DUSD.
    uint256 dusdBalance;
}

interface IDusdPegOracleCurveErrors {
    /// @notice Error thrown when a required address is zero
    error DusdPegOracleCurveZeroAddress();

    /// @notice Error thrown when a required numeric configuration value is zero
    error DusdPegOracleCurveInvalidConfig();

    /// @notice Error thrown when the pool or factory does not report exactly two coins
    error DusdPegOracleCurveInvalidCoinCount();

    /// @notice Error thrown when coin 0 is not the quote token or coin 1 is not DUSD
    error DusdPegOracleCurveInvalidCoinOrder();

    /// @notice Error thrown when the pool's EMA averaging time does not match the approved value
    error DusdPegOracleCurveInvalidMaExpTime();

    /// @notice Error thrown when the pool's current or future amplification differs from the approved value
    error DusdPegOracleCurveInvalidAmplification();

    /// @notice Error thrown when the factory reports an unexpected number of asset types
    error DusdPegOracleCurveInvalidAssetTypeCount();

    /// @notice Error thrown when a coin is not registered as a standard ERC-20 asset
    /// @param index Index of the unsupported coin
    /// @param assetType Curve asset-type identifier reported by the factory
    error DusdPegOracleCurveUnsupportedAssetType(uint256 index, uint8 assetType);

    /// @notice Error thrown when the factory identifies the pool as a metapool
    error DusdPegOracleCurveUnsupportedMetapool();

    /// @notice Error thrown when the factory does not recognize the configured pool
    error DusdPegOracleCurvePoolNotRegistered();

    /// @notice Error thrown when the pool does not expose the expected EMA price
    error DusdPegOracleCurveOracleUnavailable();

    /// @notice Error thrown when the factory reports an implementation other than the approved implementation
    /// @param actual Implementation reported by the factory
    /// @param expected Implementation supplied in the immutable configuration
    error DusdPegOracleCurveUnexpectedImplementation(address actual, address expected);
}

interface IDusdPegOracleCurveEvents {
    /// @notice Emitted when the owner updates runtime check status
    /// @param enabled Whether the checks were enabled
    event SetRuntimeChecks(bool enabled);
}

interface IDusdPegOracleCurveBase is IDusdPegOracleCurveErrors, IDusdPegOracleCurveEvents {
    /// @notice A two-coin pool exposes one oracle price: coin 1 relative to coin 0.
    function ORACLE_INDEX() external view returns (uint256);

    /// @notice The expected number of coins supported by the pool.
    function EXPECTED_COIN_COUNT() external view returns (uint256);

    /// @notice Curve asset type 0 identifies a standard ERC-20 with no special price handling.
    function STANDARD_ASSET_TYPE() external view returns (uint8);

    /// @notice The Curve price timestamp occupies the low 128 bits.
    function PRICE_TIMESTAMP_MASK() external view returns (uint256);

    /// @notice Returns the configured Curve pool.
    function pool() external view returns (address);

    /// @notice Returns the factory used to verify the pool.
    function factory() external view returns (address);

    /// @notice Returns the approved Curve pool implementation.
    function poolImplementation() external view returns (address);

    /// @notice Returns the configured DUSD token.
    function dusd() external view returns (address);

    /// @notice Returns the configured USD-par quote token.
    function quoteToken() external view returns (address);

    /// @notice Returns the approved Curve EMA averaging time.
    function expectedMaExpTime() external view returns (uint256);

    /// @notice Returns the approved amplification coefficient.
    function expectedAPrecise() external view returns (uint256);

    /// @notice Returns whether runtime configuration checks are enabled.
    function runtimeConfigChecksEnabled() external view returns (bool);

    /// @notice Returns the current DUSD/USD price and associated metadata.
    /// @return priceWad DUSD/USD price using 1e18 precision.
    /// @return observedAt Timestamp represented by the observation.
    /// @return valid Whether the observation passed the oracle checks.
    function getPrice() external view returns (uint256 priceWad, uint48 observedAt, bool valid);

    /// @notice Updates the runtime validation checks.
    /// @param enabled Whether to enable the checks.
    /// @dev Only callable by the contract owner.
    function setRuntimeChecks(bool enabled) external;
}

/// @title IDusdPegOracleCurve
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for an immutable DUSD peg oracle backed by a two-coin
/// Curve StableSwap NG pool.
interface IDusdPegOracleCurve is IDusdPegOracleCurveBase {
    /// @notice Returns an unvalidated snapshot of the underlying Curve pool.
    /// @return state Unvalidated pool state at the current block.
    /// @dev This function deliberately performs no source validation, error
    /// handling, or freshness checks and may revert if a pool read fails. It is
    /// intended only for monitoring and debugging.
    function rawPoolState() external view returns (DusdPegOracleCurveRawPoolState memory state);
}

interface IDusdPegOracleCurveStaticTypes is IDusdPegOracleCurveBase {
    /// @notice Returns an unvalidated snapshot of the underlying Curve pool.
    /// @return currentStatePriceWad Instantaneous AMM state price returned by `get_p(0)`.
    /// @return lastStatePriceWad Most recent AMM state price stored by Curve.
    /// @return storedEmaPriceWad EMA value stored at Curve's most recent oracle update.
    /// @return currentEmaPriceWad EMA projected by Curve to the current block timestamp.
    /// @return priceUpdatedAt Timestamp of Curve's most recent stored price update.
    /// @return invariantUpdatedAt Timestamp of Curve's most recent stored invariant update.
    /// @return maExpTime Pool's current EMA averaging time.
    /// @return aPrecise Pool's current amplification coefficient, including Curve's precision factor.
    /// @return futureAPrecise Pool's target amplification coefficient.
    /// @return quoteTokenBalance Current balance of coin 0, the quote token.
    /// @return dusdBalance Current balance of coin 1, DUSD.
    /// @dev This function deliberately performs no source validation, error
    /// handling, or freshness checks and may revert if a pool read fails. It is
    /// intended only for monitoring and debugging.
    function rawPoolState()
        external
        view
        returns (
            uint256 currentStatePriceWad,
            uint256 lastStatePriceWad,
            uint256 storedEmaPriceWad,
            uint256 currentEmaPriceWad,
            uint256 priceUpdatedAt,
            uint256 invariantUpdatedAt,
            uint256 maExpTime,
            uint256 aPrecise,
            uint256 futureAPrecise,
            uint256 quoteTokenBalance,
            uint256 dusdBalance
        );
}
