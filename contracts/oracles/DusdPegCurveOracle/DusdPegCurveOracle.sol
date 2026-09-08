// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    DusdPegCurveOracleRawPoolState,
    DusdPegCurveOracleRuntimeConfig,
    DusdPegCurveOracleValidationConfig,
    IDusdPegCurveOracle,
    IDusdPegCurveOracleBase
} from "@alto/oracles/interfaces/IDusdPegCurveOracle.sol";
import {ICurveStableSwapNGOracle} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {ICurveStableSwapNGFactory} from "@alto/interfaces/curve/ICurveStableSwapNGFactory.sol";
import {IDusdPegOracle} from "@alto/oracles/interfaces/IDusdPegOracle.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @title DUSD/quoteToken Curve Peg Oracle
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Supplies the DUSD peg-responsive interest-rate model with the EMA
/// price of DUSD quoted in the deployment-approved reference token.
/// @dev The oracle accepts only a factory-registered, non-meta, two-coin Curve
/// StableSwap NG pool whose coin order is [quote token, DUSD] and whose coins
/// are both registered as standard ERC-20 assets. The controlled price is
/// intentionally DUSD/quoteToken, not necessarily DUSD/USD. Deployment governance
/// must configure `quoteToken` as an economically reviewed reference asset; the
/// currently intended deployment uses frxUSD.
/// @dev The pool implementation, EMA averaging time, and amplification coefficient
/// are approved at deployment. Every validated read checks the current and
/// future amplification and the averaging time. The owner may approve new EMA
/// and amplification values only when they match the pool's current state. The
/// returned timestamp is Curve's last stored price-update timestamp; the PRM,
/// rather than this oracle, applies its configured maximum observation age.
/// @dev `rawPoolState()` exposes unvalidated pool diagnostics for monitoring only.
/// @custom:audit Pending
contract DusdPegCurveOracle is AltoOwnable2Step, IDusdPegCurveOracle {
    using SafeCast for uint256;

    /// @inheritdoc IDusdPegCurveOracleBase
    uint256 public constant ORACLE_INDEX = 0;

    /// @inheritdoc IDusdPegCurveOracleBase
    uint256 public constant EXPECTED_COIN_COUNT = 2;

    /// @inheritdoc IDusdPegCurveOracleBase
    uint8 public constant STANDARD_ASSET_TYPE = 0;

    /// @inheritdoc IDusdPegCurveOracleBase
    uint256 public constant PRICE_TIMESTAMP_MASK = type(uint128).max;

    /// @inheritdoc IDusdPegCurveOracleBase
    address public immutable curvePool;

    /// @inheritdoc IDusdPegCurveOracleBase
    DusdPegCurveOracleRuntimeConfig public runtimeConfig;

    /// @notice Deploys an oracle bound to a verified pool and its factory metadata.
    /// @param curvePoolAddress   Curve StableSwap NG pool used by the oracle.
    /// @param initialRuntimeConfig Initial approved pool parameters checked by the deployed oracle.
    /// @param validationConfig   Pool identity and provenance checked only during deployment.
    /// @param initialOwner       The contract's initial owner.
    constructor(
        address curvePoolAddress,
        DusdPegCurveOracleRuntimeConfig memory initialRuntimeConfig,
        DusdPegCurveOracleValidationConfig memory validationConfig,
        address initialOwner
    ) Ownable(initialOwner) {
        _assertNonZero(curvePoolAddress);
        _assertNonZero(validationConfig.expectedCurvePoolImplementation);
        _assertNonZero(validationConfig.curveFactory);
        _assertNonZero(validationConfig.dusd);
        _assertNonZero(validationConfig.quoteToken);

        if (validationConfig.dusd == validationConfig.quoteToken) {
            revert DusdPegCurveOracleIdenticalCoins();
        }

        _assertNonZero(initialRuntimeConfig.expectedMaExpTime);
        _assertNonZero(initialRuntimeConfig.expectedAPrecise);

        _verifyAgainstPool(curvePoolAddress, initialRuntimeConfig, validationConfig);
        _verifyAgainstFactory(curvePoolAddress, validationConfig);

        curvePool = curvePoolAddress;
        runtimeConfig = initialRuntimeConfig;
    }

    /// @inheritdoc IDusdPegCurveOracleBase
    function setRuntimeConfig(DusdPegCurveOracleRuntimeConfig calldata newRuntimeConfig) external onlyOwner {
        _assertNonZero(newRuntimeConfig.expectedMaExpTime);
        _assertNonZero(newRuntimeConfig.expectedAPrecise);

        _verifyRuntimeConfig(ICurveStableSwapNGOracle(curvePool), newRuntimeConfig);

        runtimeConfig = newRuntimeConfig;

        emit SetRuntimeConfig(newRuntimeConfig);
    }

    /// @inheritdoc IDusdPegOracle
    function getPrice() external view returns (uint256 priceWad, uint48 observedAt, bool valid) {
        ICurveStableSwapNGOracle curvePoolContract = ICurveStableSwapNGOracle(curvePool);
        uint256 observedAtRaw = curvePoolContract.ma_last_time() & PRICE_TIMESTAMP_MASK;

        if (observedAtRaw == 0 || observedAtRaw > block.timestamp || observedAtRaw > type(uint48).max) {
            return (0, 0, false);
        }

        observedAt = observedAtRaw.toUint48();

        if (!_validCurrentState()) return (0, observedAt, false);

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
        // 2. The approved controller price is DUSD/quoteToken. It intentionally
        // does not compose this value with quoteToken/USD. A quote-token depeg is
        // therefore an accepted basis risk of the controller definition and must
        // be monitored separately rather than being interpreted as DUSD/USD here.
        // ---------------------------------------------------------------------
        priceWad = curvePoolContract.price_oracle(ORACLE_INDEX);
        if (priceWad == 0) return (0, observedAt, false);

        // A price far below the peg is still valid as far as the oracle is
        // concerned. The PRM, not the oracle, decides what interest rate
        // corresponds to that price.
        //
        // The oracle does not apply any maxOracleAge. It reports the source
        // timestamp and lets the PRM apply its configured freshness policy.
        return (priceWad, observedAt, true);
    }

    /// @inheritdoc IDusdPegCurveOracle
    function rawPoolState() external view returns (DusdPegCurveOracleRawPoolState memory state) {
        ICurveStableSwapNGOracle curvePoolContract = ICurveStableSwapNGOracle(curvePool);
        uint256 packedTimestamps = curvePoolContract.ma_last_time();
        uint256[] memory balances = curvePoolContract.get_balances();

        state.currentStatePriceWad = curvePoolContract.get_p(ORACLE_INDEX);
        state.lastStatePriceWad = curvePoolContract.last_price(ORACLE_INDEX);
        state.storedEmaPriceWad = curvePoolContract.ema_price(ORACLE_INDEX);
        state.currentEmaPriceWad = curvePoolContract.price_oracle(ORACLE_INDEX);

        state.priceUpdatedAt = packedTimestamps & PRICE_TIMESTAMP_MASK;
        state.invariantUpdatedAt = packedTimestamps >> 128;

        state.maExpTime = curvePoolContract.ma_exp_time();
        state.aPrecise = curvePoolContract.A_precise();
        state.futureAPrecise = curvePoolContract.future_A();

        // The constructor verifies a two-coin pool with the direct
        // [quote token, DUSD] order.
        state.quoteTokenBalance = balances[0];
        state.dusdBalance = balances[1];
    }

    /// @dev Verifies that Curve's live controller-relevant configuration still
    /// matches the configuration against which this oracle was approved.
    /// @return valid Whether all live parameters match their approved values.
    function _validCurrentState() private view returns (bool valid) {
        ICurveStableSwapNGOracle curvePoolContract = ICurveStableSwapNGOracle(curvePool);
        DusdPegCurveOracleRuntimeConfig memory config = runtimeConfig;
        return curvePoolContract.ma_exp_time() == config.expectedMaExpTime
            && curvePoolContract.A_precise() == config.expectedAPrecise
            && curvePoolContract.future_A() == config.expectedAPrecise;
    }

    /// @dev Verifies the pool's coin layout, oracle availability, EMA averaging
    /// time, and current and future amplification against the proposed configs.
    /// @param curvePoolAddress Curve StableSwap NG pool proposed for approval.
    /// @param proposedRuntimeConfig Initial approved pool parameters.
    /// @param validationConfig Pool identity checked only during deployment.
    function _verifyAgainstPool(
        address curvePoolAddress,
        DusdPegCurveOracleRuntimeConfig memory proposedRuntimeConfig,
        DusdPegCurveOracleValidationConfig memory validationConfig
    ) private view {
        ICurveStableSwapNGOracle curvePoolContract = ICurveStableSwapNGOracle(curvePoolAddress);

        if (curvePoolContract.N_COINS() != EXPECTED_COIN_COUNT) {
            revert DusdPegCurveOracleInvalidCoinCount();
        }

        // Require the direct, non-inverted oracle orientation.
        if (
            curvePoolContract.coins(0) != validationConfig.quoteToken
                || curvePoolContract.coins(1) != validationConfig.dusd
        ) {
            revert DusdPegCurveOracleInvalidCoinOrder();
        }

        _verifyRuntimeConfig(curvePoolContract, proposedRuntimeConfig);

        try curvePoolContract.price_oracle(ORACLE_INDEX) returns (uint256) {}
        catch {
            revert DusdPegCurveOracleOracleUnavailable();
        }
    }

    /// @dev Verifies the pool's EMA averaging time and current and future
    /// amplification against proposed approved values.
    function _verifyRuntimeConfig(
        ICurveStableSwapNGOracle curvePoolContract,
        DusdPegCurveOracleRuntimeConfig memory proposedRuntimeConfig
    ) private view {
        if (curvePoolContract.ma_exp_time() != proposedRuntimeConfig.expectedMaExpTime) {
            revert DusdPegCurveOracleInvalidMaExpTime();
        }

        // `future_A` catches a newly initiated ramp before `A_precise` has moved
        // materially away from its starting value.
        if (
            curvePoolContract.A_precise() != proposedRuntimeConfig.expectedAPrecise
                || curvePoolContract.future_A() != proposedRuntimeConfig.expectedAPrecise
        ) {
            revert DusdPegCurveOracleInvalidAmplification();
        }
    }

    /// @dev Verifies the pool's factory registration, implementation, pool
    /// classification, coin order, and standard ERC-20 asset types.
    /// @param curvePoolAddress Curve pool proposed for approval.
    /// @param validationConfig Pool identity and provenance checked during deployment.
    function _verifyAgainstFactory(address curvePoolAddress, DusdPegCurveOracleValidationConfig memory validationConfig)
        private
        view
    {
        // On pool deployment, the Factory registers a number of details that we
        // can use as a provenance check.
        ICurveStableSwapNGFactory curveFactory = ICurveStableSwapNGFactory(validationConfig.curveFactory);

        if (curveFactory.get_n_coins(curvePoolAddress) != EXPECTED_COIN_COUNT) {
            revert DusdPegCurveOracleInvalidCoinCount();
        }

        if (curveFactory.is_meta(curvePoolAddress)) {
            revert DusdPegCurveOracleUnsupportedMetapool();
        }

        address[] memory registeredCoins = curveFactory.get_coins(curvePoolAddress);

        if (registeredCoins.length != EXPECTED_COIN_COUNT) {
            revert DusdPegCurveOracleInvalidCoinCount();
        }

        if (registeredCoins[0] != validationConfig.quoteToken || registeredCoins[1] != validationConfig.dusd) {
            revert DusdPegCurveOracleInvalidCoinOrder();
        }

        uint8[] memory assetTypes = curveFactory.get_pool_asset_types(curvePoolAddress);

        if (assetTypes.length != EXPECTED_COIN_COUNT) {
            revert DusdPegCurveOracleInvalidAssetTypeCount();
        }

        for (uint256 i; i < EXPECTED_COIN_COUNT; ++i) {
            if (assetTypes[i] != STANDARD_ASSET_TYPE) {
                revert DusdPegCurveOracleUnsupportedAssetType(i, assetTypes[i]);
            }
        }

        address actualCurvePoolImplementation = curveFactory.get_implementation_address(curvePoolAddress);

        if (actualCurvePoolImplementation == address(0)) {
            revert DusdPegCurveOraclePoolNotRegistered();
        }

        if (actualCurvePoolImplementation != validationConfig.expectedCurvePoolImplementation) {
            revert DusdPegCurveOracleUnexpectedImplementation(
                actualCurvePoolImplementation, validationConfig.expectedCurvePoolImplementation
            );
        }
    }

    /// @dev Reverts when `value` is the zero address.
    /// @param value Address to validate.
    function _assertNonZero(address value) private pure {
        if (value == address(0)) revert DusdPegCurveOracleZeroAddress();
    }

    /// @dev Reverts when `value` is zero.
    /// @param value Numeric configuration value to validate.
    function _assertNonZero(uint256 value) private pure {
        if (value == 0) revert DusdPegCurveOracleInvalidConfig();
    }
}
