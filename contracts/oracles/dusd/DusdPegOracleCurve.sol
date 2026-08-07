// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    DusdPegOracleCurveConfig,
    DusdPegOracleCurveRawPoolState,
    IDusdPegOracleCurve,
    IDusdPegOracleCurveBase
} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";
import {ICurveStableSwap} from "@alto/oracles/interfaces/ICurveStableSwap.sol";
import {ICurveStableSwapFactory} from "@alto/oracles/dusd/interfaces/ICurveStableSwapFactory.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @title DUSD Curve Peg Oracle
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Supplies the DUSD peg-responsive interest-rate model with the EMA
/// price of DUSD quoted in an immutable USD-par reference token.
/// @dev The oracle accepts only a factory-registered, non-meta, two-coin Curve
/// StableSwap NG pool whose coin order is [quote token, DUSD] and whose coins
/// are both registered as standard ERC-20 assets. Treating the returned quote
/// as a DUSD/USD price assumes that the quote token remains worth one USD.
/// @dev The pool implementation, EMA averaging time, and amplification coefficient
/// are approved at deployment. Every validated read checks the current and
/// future amplification and the averaging time against those immutable values if
/// runtime checks are enabled. The returned timestamp is Curve's last stored
/// price-update timestamp; the PRM, rather than this oracle, applies its
/// configured maximum observation age.
/// @dev `rawPoolState()` exposes unvalidated pool diagnostics for monitoring only.
contract DusdPegOracleCurve is AltoOwnable2Step, IDusdPegOracleCurve {
    using SafeCast for uint256;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public constant ORACLE_INDEX = 0;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public constant EXPECTED_COIN_COUNT = 2;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint8 public constant STANDARD_ASSET_TYPE = 0;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public constant PRICE_TIMESTAMP_MASK = type(uint128).max;

    /// @inheritdoc IDusdPegOracleCurveBase
    address public immutable pool;

    /// @inheritdoc IDusdPegOracleCurveBase
    address public immutable factory;

    /// @inheritdoc IDusdPegOracleCurveBase
    address public immutable poolImplementation;

    /// @inheritdoc IDusdPegOracleCurveBase
    address public immutable dusd;

    /// @inheritdoc IDusdPegOracleCurveBase
    address public immutable quoteToken;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public immutable expectedMaExpTime;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public immutable expectedAPrecise;

    /// @inheritdoc IDusdPegOracleCurveBase
    bool public runtimeConfigChecksEnabled;

    /// @notice Deploys an immutable oracle after verifying the pool against its
    /// live state and factory metadata.
    /// @param cfg              Pool identity and controller-relevant parameters to approve.
    /// @param runtimeChecks    Whether runtime checks are enabled.
    /// @param initialOwner     The contract's initial owner.
    constructor(DusdPegOracleCurveConfig memory cfg, bool runtimeChecks, address initialOwner) Ownable(initialOwner) {
        _assertNonZero(cfg.pool);
        _assertNonZero(cfg.poolImpl);
        _assertNonZero(cfg.factory);
        _assertNonZero(cfg.dusd);
        _assertNonZero(cfg.quoteToken);

        _assertNonZero(cfg.maExpTime);
        _assertNonZero(cfg.aPrecise);

        _verifyAgainstPool(cfg);
        _verifyAgainstFactory(cfg);

        pool = cfg.pool;
        factory = cfg.factory;
        poolImplementation = cfg.poolImpl;

        dusd = cfg.dusd;
        quoteToken = cfg.quoteToken;

        expectedMaExpTime = cfg.maExpTime;
        expectedAPrecise = cfg.aPrecise;

        runtimeConfigChecksEnabled = runtimeChecks;
    }

    /// @inheritdoc IDusdPegOracleCurveBase
    function setRuntimeChecks(bool enabled) external onlyOwner {
        emit SetRuntimeChecks(enabled);
        runtimeConfigChecksEnabled = enabled;
    }

    /// @inheritdoc IDusdPegOracleCurveBase
    function getPrice() external view returns (uint256 priceWad, uint48 observedAt, bool valid) {
        ICurveStableSwap curvePool = ICurveStableSwap(pool);
        uint256 observedAtRaw = curvePool.ma_last_time() & PRICE_TIMESTAMP_MASK;

        if (observedAtRaw == 0 || observedAtRaw > block.timestamp || observedAtRaw > type(uint48).max) {
            return (0, 0, false);
        }

        observedAt = observedAtRaw.toUint48();

        if (runtimeConfigChecksEnabled && !_validCurrentState()) return (0, observedAt, false);

        // ---------------------------------------------------------------------
        // NOTE: Potential hardening that is intentionally out of scope:
        //
        // 1. A minimum-liquidity policy could reject observations when either
        // normalized pool reserve falls below a configured threshold. Those
        // thresholds should be derived from manipulation-cost analysis that
        // considers A, pool fees, the EMA time constant, expected checkpoint
        // frequency, and available external liquidity. Reserve floors provide
        // defense in depth but do not, by themselves, guarantee manipulation
        // resistance.
        //
        // 2. The Curve price is DUSD quoted in `quoteToken`, not necessarily
        // DUSD/USD. A composite oracle could combine it with a separately
        // configured quoteToken/USD feed:
        //
        //     DUSD/USD = DUSD/quoteToken * quoteToken/USD
        //
        // Both inputs would require independent precision, freshness, validity,
        // and orientation checks. The composite observation timestamp should be
        // the older of the two source timestamps.
        // ---------------------------------------------------------------------
        priceWad = curvePool.price_oracle(ORACLE_INDEX);
        if (priceWad == 0) return (0, observedAt, false);

        // A price far below the peg is still valid as far as the oracle is
        // concerned. The PRM, not the oracle, decides what interest rate
        // corresponds to that price.
        //
        // The oracle does not apply any maxOracleAge. It reports the source
        // timestamp and lets the PRM apply its configured freshness policy.
        return (priceWad, observedAt, true);
    }

    /// @inheritdoc IDusdPegOracleCurve
    function rawPoolState() external view returns (DusdPegOracleCurveRawPoolState memory state) {
        ICurveStableSwap curvePool = ICurveStableSwap(pool);
        uint256 packedTimestamps = curvePool.ma_last_time();
        uint256[] memory balances = curvePool.get_balances();

        state.currentStatePriceWad = curvePool.get_p(ORACLE_INDEX);
        state.lastStatePriceWad = curvePool.last_price(ORACLE_INDEX);
        state.storedEmaPriceWad = curvePool.ema_price(ORACLE_INDEX);
        state.currentEmaPriceWad = curvePool.price_oracle(ORACLE_INDEX);

        state.priceUpdatedAt = packedTimestamps & PRICE_TIMESTAMP_MASK;
        state.invariantUpdatedAt = packedTimestamps >> 128;

        state.maExpTime = curvePool.ma_exp_time();
        state.aPrecise = curvePool.A_precise();
        state.futureAPrecise = curvePool.future_A();

        // The constructor verifies a two-coin pool with the direct
        // [quote token, DUSD] order.
        state.quoteTokenBalance = balances[0];
        state.dusdBalance = balances[1];
    }

    /// @dev Verifies that Curve's live controller-relevant configuration still
    /// matches the configuration against which this oracle was approved.
    /// @return valid Whether all live parameters match their approved values.
    function _validCurrentState() private view returns (bool valid) {
        ICurveStableSwap curvePool = ICurveStableSwap(pool);
        if (curvePool.ma_exp_time() != expectedMaExpTime) return false;
        if (curvePool.A_precise() != expectedAPrecise) return false;
        if (curvePool.future_A() != expectedAPrecise) return false;
        return true;
    }

    /// @dev Verifies the pool's coin layout, oracle availability, EMA averaging
    /// time, and current and future amplification against `cfg`.
    /// @param cfg Pool configuration proposed for approval.
    function _verifyAgainstPool(DusdPegOracleCurveConfig memory cfg) private view {
        ICurveStableSwap curvePool = ICurveStableSwap(cfg.pool);

        if (curvePool.N_COINS() != EXPECTED_COIN_COUNT) {
            revert DusdPegOracleCurveInvalidCoinCount();
        }

        // Require the direct, non-inverted oracle orientation.
        if (curvePool.coins(0) != cfg.quoteToken || curvePool.coins(1) != cfg.dusd) {
            revert DusdPegOracleCurveInvalidCoinOrder();
        }

        if (curvePool.ma_exp_time() != cfg.maExpTime) {
            revert DusdPegOracleCurveInvalidMaExpTime();
        }

        // `future_A` catches a newly initiated ramp before `A_precise` has moved
        // materially away from its starting value.
        if (curvePool.A_precise() != cfg.aPrecise || curvePool.future_A() != cfg.aPrecise) {
            revert DusdPegOracleCurveInvalidAmplification();
        }

        try curvePool.price_oracle(ORACLE_INDEX) returns (uint256) {}
        catch {
            revert DusdPegOracleCurveOracleUnavailable();
        }
    }

    /// @dev Verifies the pool's factory registration, implementation, pool
    /// classification, coin order, and standard ERC-20 asset types.
    /// @param cfg Pool configuration proposed for approval.
    function _verifyAgainstFactory(DusdPegOracleCurveConfig memory cfg) private view {
        // On pool deployment, the Factory registers a number of details that we
        // can use as a provenance check.
        ICurveStableSwapFactory curveFactory = ICurveStableSwapFactory(cfg.factory);

        if (curveFactory.get_n_coins(cfg.pool) != EXPECTED_COIN_COUNT) {
            revert DusdPegOracleCurveInvalidCoinCount();
        }

        if (curveFactory.is_meta(cfg.pool)) {
            revert DusdPegOracleCurveUnsupportedMetapool();
        }

        address[] memory registeredCoins = curveFactory.get_coins(cfg.pool);

        if (registeredCoins.length != EXPECTED_COIN_COUNT) {
            revert DusdPegOracleCurveInvalidCoinCount();
        }

        if (registeredCoins[0] != cfg.quoteToken || registeredCoins[1] != cfg.dusd) {
            revert DusdPegOracleCurveInvalidCoinOrder();
        }

        uint8[] memory assetTypes = curveFactory.get_pool_asset_types(cfg.pool);

        if (assetTypes.length != EXPECTED_COIN_COUNT) {
            revert DusdPegOracleCurveInvalidAssetTypeCount();
        }

        for (uint256 i; i < EXPECTED_COIN_COUNT; ++i) {
            if (assetTypes[i] != STANDARD_ASSET_TYPE) {
                revert DusdPegOracleCurveUnsupportedAssetType(i, assetTypes[i]);
            }
        }

        address impl = curveFactory.get_implementation_address(cfg.pool);

        if (impl == address(0)) {
            revert DusdPegOracleCurvePoolNotRegistered();
        }

        if (impl != cfg.poolImpl) {
            revert DusdPegOracleCurveUnexpectedImplementation(impl, cfg.poolImpl);
        }
    }

    /// @dev Reverts when `value` is the zero address.
    /// @param value Address to validate.
    function _assertNonZero(address value) private pure {
        if (value == address(0)) revert DusdPegOracleCurveZeroAddress();
    }

    /// @dev Reverts when `value` is zero.
    /// @param value Numeric configuration value to validate.
    function _assertNonZero(uint256 value) private pure {
        if (value == 0) revert DusdPegOracleCurveInvalidConfig();
    }
}
