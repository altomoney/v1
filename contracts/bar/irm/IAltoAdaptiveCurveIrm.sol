// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

struct IrmMarketData {
    uint256 totalSupplyAssets;
    uint256 totalBorrowAssets;
    uint256 elapsedSeconds;
    int256 currentRateAtTarget;
}

struct IrmConfiguration {
    /// @notice Curve steepness (scaled by WAD).
    /// @dev Curve steepness = 4.
    int256 curveSteepness;
    /// @notice Adjustment speed per second (scaled by WAD).
    /// @dev The speed is per second, so the rate moves at a speed of ADJUSTMENT_SPEED * err each second (while being
    /// continuously compounded).
    /// @dev Adjustment speed = 50/year.
    int256 adjustmentSpeed;
    /// @notice Target utilization (scaled by WAD).
    /// @dev Target utilization = 90%.
    int256 targetUtilization;
    /// @notice Initial rate at target per second (scaled by WAD).
    /// @dev Initial rate at target = 4% (rate between 1% and 16%).
    int256 initialRateAtTarget;
    /// @notice Minimum rate at target per second (scaled by WAD).
    /// @dev Minimum rate at target = 0.1% (minimum rate = 0.025%).
    int256 minRateAtTarget;
    /// @notice Maximum rate at target per second (scaled by WAD).
    /// @dev Maximum rate at target = 200% (maximum rate = 800%).
    int256 maxRateAtTarget;
}

/// @title IAltoAdaptiveCurveIrm
/// @author Alto Labs
/// @custom:contact security@alto.money
interface IAltoAdaptiveCurveIrm {
    function getAccruedInterest(IrmMarketData calldata market, IrmConfiguration calldata irmConfiguration, uint256 fee)
        external
        pure
        returns (uint256 interest, uint256 feeAmount, uint256 avgRate, int256 endRateAtTarget);

    /// @dev Returns avgRate and endRateAtTarget.
    function getBorrowRate(IrmMarketData calldata market, IrmConfiguration calldata irmConfiguration)
        external
        pure
        returns (uint256, int256);
}
