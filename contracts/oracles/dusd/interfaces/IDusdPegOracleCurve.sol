// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IDusdPegOracle} from "@alto/oracles/interfaces/IDusdPegOracle.sol";
import {ICurveStableSwap} from "@alto/oracles/interfaces/ICurveStableSwap.sol";
import {ICurveStableSwapFactory} from "@alto/oracles/interfaces/ICurveStableSwapFactory.sol";

/// @title DUSD Curve Peg Oracle Interface
///
/// @author Alto
///
/// @custom:contact security@altofoundation.org
///
/// @notice Interface for an immutable DUSD peg oracle backed by a two-coin
/// Curve StableSwap NG pool.
interface IDusdPegOracleCurve is IDusdPegOracle {
    // ========================================================================
    // Type Declarations
    // ========================================================================

    /// @notice Immutable pool identity and controller-relevant parameters.
    struct Config {
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
    ///
    /// @dev Values are returned directly from the pool and are not approved for
    /// use by the PRM.
    struct RawPoolState {
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

    // ========================================================================
    // Events
    // ========================================================================

    /// @notice Emitted when the owner updates runtime check status.
    ///
    /// @param enabled Whether the checks were enabled.
    event SetRuntimeChecks(bool enabled);

    // ========================================================================
    // Errors
    // ========================================================================

    /// @notice Thrown when a required address is zero.
    error DusdPegOracleCurve__ZeroAddress();

    /// @notice Thrown when a required numeric configuration value is zero.
    error DusdPegOracleCurve__InvalidConfig();

    /// @notice Thrown when the pool or factory does not report exactly two coins.
    error DusdPegOracleCurve__InvalidCoinCount();

    /// @notice Thrown when coin 0 is not the quote token or coin 1 is not DUSD.
    error DusdPegOracleCurve__InvalidCoinOrder();

    /// @notice Thrown when the pool's EMA averaging time does not match the
    /// approved value.
    error DusdPegOracleCurve__InvalidMaExpTime();

    /// @notice Thrown when the pool's current or future amplification differs
    /// from the approved value.
    error DusdPegOracleCurve__InvalidAmplification();

    /// @notice Thrown when the factory reports an unexpected number of asset types.
    error DusdPegOracleCurve__InvalidAssetTypeCount();

    /// @notice Thrown when a coin is not registered as a standard ERC-20 asset.
    ///
    /// @param index        Index of the unsupported coin.
    /// @param assetType    Curve asset-type identifier reported by the factory.
    error DusdPegOracleCurve__UnsupportedAssetType(uint256 index, uint8 assetType);

    /// @notice Thrown when the factory identifies the pool as a metapool.
    error DusdPegOracleCurve__UnsupportedMetapool();

    /// @notice Thrown when the factory does not recognize the configured pool.
    error DusdPegOracleCurve__PoolNotRegistered();

    /// @notice Thrown when the pool does not expose the expected EMA price.
    error DusdPegOracleCurve__CurveOracleUnavailable();

    /// @notice Thrown when the factory reports an implementation other than the
    /// approved implementation.
    ///
    /// @param actual   Implementation reported by the factory.
    /// @param expected Implementation supplied in the immutable configuration.
    error DusdPegOracleCurve__UnexpectedImplementation(address actual, address expected);

    // ========================================================================
    // Functions
    // ========================================================================

    /// @notice Updates the runtime validation checks.
    ///
    /// @param enabled Whether to enable the checks.
    ///
    /// @dev Only callable by the contract owner.
    function setRuntimeChecks(bool enabled) external;

    /// @notice Returns an unvalidated snapshot of the underlying Curve pool.
    ///
    /// @return state Unvalidated pool state at the current block.
    ///
    /// @dev This function deliberately performs no source validation, error
    /// handling, or freshness checks and may revert if a pool read fails. It is
    /// intended only for monitoring and debugging.
    function rawPoolState() external view returns (RawPoolState memory state);

    /// @notice Returns the configured Curve pool.
    ///
    /// @return curvePool Configured Curve pool.
    function pool() external view returns (ICurveStableSwap curvePool);

    /// @notice Returns the factory used to verify the pool.
    ///
    /// @return curveFactory Factory used to verify the pool.
    function factory() external view returns (ICurveStableSwapFactory curveFactory);

    /// @notice Returns the approved Curve pool implementation.
    ///
    /// @return impl Approved implementation address.
    function poolImplementation() external view returns (address impl);

    /// @notice Returns the configured DUSD token.
    ///
    /// @return token DUSD token address.
    function dusd() external view returns (address token);

    /// @notice Returns the configured USD-par quote token.
    ///
    /// @return token Quote-token address.
    function quoteToken() external view returns (address token);

    /// @notice Returns the approved Curve EMA averaging time.
    ///
    /// @return value Approved EMA exponential time constant, in seconds.
    function expectedMaExpTime() external view returns (uint256 value);

    /// @notice Returns the approved amplification coefficient.
    ///
    /// @return value Approved amplification coefficient, including Curve's precision factor.
    function expectedAPrecise() external view returns (uint256 value);

    /// @notice Returns whether runtime configuration checks are enabled.
    ///
    /// @return enabled True if checks are enabled, false otherwise.
    function runtimeConfigChecksEnabled() external view returns (bool enabled);
}
