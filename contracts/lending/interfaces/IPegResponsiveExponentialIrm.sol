// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

/// @notice Parameters for the price-to-rate curve, recovery confirmation,
/// and oracle freshness.
/// @dev Each rate is a continuously compounded SPY value, not an annual
/// percentage yield. Prices and `doublingDistance` use 1e18 precision.
struct PegResponsiveExponentialIrmConfig {
    /// @dev Price at or above which the raw curve returns `baseRate`.
    uint256 recoveryPrice;
    /// @dev Price below which the raw curve grows exponentially.
    uint256 stressPrice;
    /// @dev Minimum SPY rate returned at or above `recoveryPrice`. May be zero.
    uint256 baseRate;
    /// @dev SPY rate returned at `stressPrice` and stress-mode rate floor. Must be nonzero.
    uint256 stressRate;
    /// @dev Extreme safety ceiling for the SPY rate.
    uint256 maxRate;
    /// @dev Price decline below `stressPrice` that doubles `stressRate`.
    /// The stressed curve is `stressRate * 2 ** (depeg / doublingDistance)`.
    /// For example, 0.0025e18 maps 7.5% at $0.995 to 30% at $0.990.
    uint256 doublingDistance;
    /// @dev Minimum block-time delay between qualifying recovery observations.
    /// This confirms sampled recovery, not a continuously healthy price.
    uint48 recoveryDelay;
    /// @dev Maximum permitted age of an oracle observation.
    /// Configure below recoveryDelay to prevent reuse of one observation for recovery.
    /// This relationship is not enforced on-chain.
    uint48 maxOracleAge;
}

/// @notice Internal cached state of the interest rate model.
struct IRState {
    /// @dev SPY rate that will accrue during the next interval.
    uint256 borrowRate;
    /// @dev Timestamp through which interest has been accrued.
    uint48 lastUpdate;
    /// @dev Timestamp at which the current recovery confirmation began.
    uint48 recoveryStartedAt;
    /// @dev Whether the controller is enforcing the stress-rate floor.
    bool stressMode;
}

interface IPegResponsiveExponentialIrmErrors {
    /// @notice Error thrown when the peg oracle address is invalid
    error PegResponsiveExponentialIrmInvalidOracle();

    /// @notice Error thrown when price thresholds are invalid
    error PegResponsiveExponentialIrmInvalidPriceConfig();

    /// @notice Error thrown when configured rates are invalid
    error PegResponsiveExponentialIrmInvalidRateConfig();

    /// @notice Error thrown when controller timing or curve parameters are invalid
    error PegResponsiveExponentialIrmInvalidControllerConfig();
}

interface IPegResponsiveExponentialIrmEvents {
    /// @notice Emitted when the peg oracle changes.
    event SetPegOracle(address indexed oldPegOracle, address indexed newPegOracle);

    /// @notice Emitted when the IRM configuration changes.
    event SetIrmConfig(PegResponsiveExponentialIrmConfig newConfig);

    /// @notice Emitted when stress-mode or recovery-confirmation state changes.
    event StressStateUpdated(bool stressMode, uint48 recoveryStartedAt, uint256 priceWad);

    /// @notice Emitted after a checkpoint or owner input change refreshes the rate.
    event BorrowRateUpdated(uint256 prev, uint256 curr, uint256 priceWad, uint48 observedAt, bool oracleValid);

    /// @notice Emitted when the interest rate state has been updated.
    event IRStateUpdated(IRState newIRState);
}

interface IPegResponsiveExponentialIrmBase is
    IIrm,
    IPegResponsiveExponentialIrmErrors,
    IPegResponsiveExponentialIrmEvents
{
    /// @notice The maximum per-second borrow rate.
    function MAX_BORROW_RATE() external view returns (uint256);

    /// @notice The maximum supported recovery price.
    function MAX_RECOVERY_PRICE() external view returns (uint256);

    /// @notice The maximum supported input to the exponential approximation.
    function MAX_EXPONENT_INPUT() external view returns (uint256);

    /// @notice Returns the active DUSD/quoteToken peg oracle.
    function pegOracle() external view returns (address);

    /// @notice Returns the market bound to this interest-rate model.
    function market() external view returns (address);

    /// @notice Checkpoints the old inputs, replaces the oracle, and refreshes the rate.
    /// @param newPegOracle The address of the new peg oracle.
    /// @dev Requirements:
    /// - Only callable by the contract owner.
    /// - New oracle address cannot be the zero address.
    /// @dev Restarts recovery confirmation. Paused and unbound markets skip accrual
    /// but still refresh the rate without changing the accrual timestamp.
    function setPegOracle(address newPegOracle) external;

    /// @notice Changes the price curve and controller configuration.
    /// @param newConfig The new IRM configuration to apply.
    /// @dev Checkpoints the old inputs before applying the new configuration and rate.
    /// Recovery confirmation restarts. An invalid observation holds the rate within
    /// the new applicable floor and cap. Paused and unbound markets skip accrual.
    /// @dev Requirements:
    /// - Only callable by the contract owner.
    /// - Configuration is validated according to `_validateConfig`.
    function setIrmConfig(PegResponsiveExponentialIrmConfig calldata newConfig) external;

    /// @notice Previews the oracle observation and rate that would be stored by a checkpoint.
    /// @return priceWad Valid DUSD/quoteToken price, or zero for an unusable observation.
    /// @return observedAt Timestamp supplied by the oracle.
    /// @return oracleValid Whether the observation passed validity and freshness checks.
    /// @return borrowRate Effective rate that would be stored for the next interval.
    function previewBorrowRate()
        external
        view
        returns (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 borrowRate);

    /// @notice Returns the raw target SPY rate for a given DUSD/quoteToken price.
    /// @param priceWad The price at which the rate will be calculated.
    /// @dev The rate curve has three regions:
    /// - At or above the recovery price: fixed at the base rate.
    /// - Between recovery and stress: linearly increases to the stress rate.
    /// - Below stress: exponentially increases, capped at the maximum rate.
    /// @dev Stress-mode hysteresis is handled separately.
    function targetBorrowRate(uint256 priceWad) external view returns (uint256 borrowRate);
}

/// @title IPegResponsiveExponentialIrm
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for the DUSD peg-responsive interest-rate model.
interface IPegResponsiveExponentialIrm is IPegResponsiveExponentialIrmBase {
    /// @notice Returns the complete price-curve and controller configuration.
    /// @return configuration The current configuration.
    function irmConfig() external view returns (PegResponsiveExponentialIrmConfig memory configuration);

    /// @notice Returns the complete cached interest-rate controller state.
    /// @return state The cached interest-rate state.
    function irState() external view returns (IRState memory state);
}

interface IPegResponsiveExponentialIrmStaticTypes is IPegResponsiveExponentialIrmBase {
    /// @notice Returns the complete price-curve and controller configuration.
    /// @return recoveryPrice Price at or above which the raw curve returns the base rate.
    /// @return stressPrice Price below which the raw curve grows exponentially.
    /// @return baseRate Minimum SPY rate returned at or above the recovery price.
    /// @return stressRate SPY rate returned at the stress price and stress-mode rate floor.
    /// @return maxRate Extreme safety ceiling for the SPY rate.
    /// @return doublingDistance Price decline below the stress price that doubles the stress rate.
    /// @return recoveryDelay Minimum block-time delay between qualifying recovery observations.
    /// @return maxOracleAge Maximum permitted age of an oracle observation.
    function irmConfig()
        external
        view
        returns (
            uint256 recoveryPrice,
            uint256 stressPrice,
            uint256 baseRate,
            uint256 stressRate,
            uint256 maxRate,
            uint256 doublingDistance,
            uint48 recoveryDelay,
            uint48 maxOracleAge
        );

    /// @notice Returns the complete cached interest-rate controller state.
    /// @return borrowRate SPY rate that will accrue during the next interval.
    /// @return lastUpdate Timestamp through which interest has been accrued.
    /// @return recoveryStartedAt Timestamp at which the current recovery confirmation began.
    /// @return stressMode Whether the controller is enforcing the stress-rate floor.
    function irState()
        external
        view
        returns (uint256 borrowRate, uint48 lastUpdate, uint48 recoveryStartedAt, bool stressMode);
}
