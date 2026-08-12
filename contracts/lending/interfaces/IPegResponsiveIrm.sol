// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

/// @notice Parameters for the price-to-rate curve, recovery confirmation,
/// and oracle freshness.
/// @dev Each rate is a continuously compounded SPY value, not an annual
/// percentage yield. Prices and `doublingDistance` use 1e18 precision.
struct CurveConfig {
    /// @dev Price at or above which the raw curve returns `baseRate`.
    uint256 recoveryPrice;
    /// @dev Price below which the raw curve grows exponentially.
    uint256 stressPrice;
    /// @dev Minimum SPY rate returned at or above `recoveryPrice`.
    uint256 baseRate;
    /// @dev SPY rate returned at `stressPrice` and stress-mode rate floor.
    uint256 stressRate;
    /// @dev Extreme safety ceiling for the SPY rate.
    uint256 maxRate;
    /// @dev Price decline below `stressPrice` that doubles `stressRate`.
    /// The stressed curve is `stressRate * 2 ** (depeg / doublingDistance)`.
    /// For example, 0.0025e18 maps 7.5% at $0.995 to 30% at $0.990.
    uint256 doublingDistance;
    /// @dev Time price must remain at or above `recoveryPrice` before stress mode exits.
    uint48 recoveryDelay;
    /// @dev Maximum permitted age of an oracle observation.
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

interface IPegResponsiveIrmErrors {
    /// @notice Error thrown when the peg oracle address is invalid
    error PegResponsiveIrmInvalidOracle();

    /// @notice Error thrown when price thresholds are invalid
    error PegResponsiveIrmInvalidPriceConfig();

    /// @notice Error thrown when configured rates are invalid
    error PegResponsiveIrmInvalidRateConfig();

    /// @notice Error thrown when controller timing or curve parameters are invalid
    error PegResponsiveIrmInvalidControllerConfig();
}

interface IPegResponsiveIrmEvents {
    /// @notice Emitted when the peg oracle changes.
    event SetPegOracle(address indexed oldPegOracle, address indexed newPegOracle);

    /// @notice Emitted when the curve configuration changes.
    event SetCurveConfig(CurveConfig newConfig);

    /// @notice Emitted when stress-mode or recovery-confirmation state changes.
    event StressStateUpdated(bool stressMode, uint48 recoveryStartedAt, uint256 priceWad);

    /// @notice Emitted after an interest checkpoint evaluates the peg controller.
    event BorrowRateUpdated(uint256 prev, uint256 curr, uint256 priceWad, uint48 observedAt, bool oracleValid);

    /// @notice Emitted when the interest rate state has been updated.
    event IRStateUpdated(IRState newIRState);
}

interface IPegResponsiveIrmBase is IIrm, IPegResponsiveIrmErrors, IPegResponsiveIrmEvents {
    /// @notice The maximum per-second borrow rate.
    function MAX_BORROW_RATE() external view returns (uint256);

    /// @notice The maximum supported recovery price.
    function MAX_RECOVERY_PRICE() external view returns (uint256);

    /// @notice The fixed-point scalar used by the controller.
    function WAD() external view returns (uint256);

    /// @notice The value of ln(2) used to evaluate the exponential curve.
    function LN_2_WAD() external view returns (uint256);

    /// @notice The maximum supported input to the exponential approximation.
    function MAX_EXPONENT_INPUT() external view returns (uint256);

    /// @notice Returns the active DUSD/quoteToken peg oracle.
    function oracle() external view returns (address);

    /// @notice Returns the market bound to this interest-rate model.
    function market() external view returns (address);

    /// @notice Changes the oracle after checkpointing the old configuration.
    /// @param _newOracle The address of the new oracle.
    /// @dev Requirements:
    /// - Only callable by the contract owner.
    /// - New oracle address cannot be the zero address.
    function setPegOracle(address _newOracle) external;

    /// @notice Changes the price curve and controller configuration.
    /// @param _newConfig The new curve configuration to apply.
    /// @dev Recovery confirmation is restarted under the new configuration.
    /// @dev Requirements:
    /// - Only callable by the contract owner.
    /// - Configuration is validated according to `_validateConfig`.
    /// - The new max rate must be greater than, or equal to, the current borrow rate.
    function setCurveConfig(CurveConfig calldata _newConfig) external;

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
    /// @param _priceWad The price at which the rate will be calculated.
    /// @dev The rate curve has three regions:
    /// - At or above the recovery price: fixed at the base rate.
    /// - Between recovery and stress: linearly increases to the stress rate.
    /// - Below stress: exponentially increases, capped at the maximum rate.
    /// @dev Stress-mode hysteresis is handled separately.
    function targetBorrowRate(uint256 _priceWad) external view returns (uint256 borrowRate);
}

/// @title IPegResponsiveIrm
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for the DUSD peg-responsive interest-rate model.
interface IPegResponsiveIrm is IPegResponsiveIrmBase {
    /// @notice Returns the complete price-curve and controller configuration.
    /// @return configuration The current configuration.
    function curveConfig() external view returns (CurveConfig memory configuration);

    /// @notice Returns the complete cached interest-rate controller state.
    /// @return state The cached interest-rate state.
    function irState() external view returns (IRState memory state);
}

interface IPegResponsiveIrmStaticTypes is IPegResponsiveIrmBase {
    /// @notice Returns the complete price-curve and controller configuration.
    /// @return recoveryPrice Price at or above which the raw curve returns the base rate.
    /// @return stressPrice Price below which the raw curve grows exponentially.
    /// @return baseRate Minimum SPY rate returned at or above the recovery price.
    /// @return stressRate SPY rate returned at the stress price and stress-mode rate floor.
    /// @return maxRate Extreme safety ceiling for the SPY rate.
    /// @return doublingDistance Price decline below the stress price that doubles the stress rate.
    /// @return recoveryDelay Time price must remain at or above the recovery price before stress mode exits.
    /// @return maxOracleAge Maximum permitted age of an oracle observation.
    function curveConfig()
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
