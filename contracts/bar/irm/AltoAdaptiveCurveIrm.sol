// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {WAD_INT, MathLib} from "./libraries/MathLib.sol";
import {WAD, MorphoMathLib} from "./libraries/MorphoMathLib.sol";
import {ExpLib} from "./libraries/ExpLib.sol";
import {UtilsLib} from "./libraries/UtilsLib.sol";
import {IAltoAdaptiveCurveIrm, IrmMarketData, IrmConfiguration} from "./IAltoAdaptiveCurveIrm.sol";

/// @title AltoAdaptiveCurveIrm
/// @author Alto Labs
/// @author Adapted from Morpho Labs (https://github.com/morpho-org/morpho-blue-irm/).
/// @custom:contact security@alto.money
contract AltoAdaptiveCurveIrm is IAltoAdaptiveCurveIrm {
    using MathLib for int256;
    using MorphoMathLib for uint256;
    using UtilsLib for int256;

    function getAccruedInterest(IrmMarketData calldata market, IrmConfiguration calldata irmConfiguration, uint256 fee)
        public
        pure
        override
        returns (uint256 interest, uint256 feeAmount, uint256 avgRate, int256 endRateAtTarget)
    {
        (avgRate, endRateAtTarget) = _getBorrowRate(market, irmConfiguration);
        interest = market.totalBorrowAssets.wMulDown(avgRate.wTaylorCompounded(market.elapsedSeconds));
        feeAmount = interest.wMulDown(fee);
        return (interest, feeAmount, avgRate, endRateAtTarget);
    }

    /// @dev Returns avgRate and endRateAtTarget.
    function getBorrowRate(IrmMarketData calldata market, IrmConfiguration calldata irmConfiguration)
        external
        pure
        override
        returns (uint256, int256)
    {
        return _getBorrowRate(market, irmConfiguration);
    }

    function _getBorrowRate(IrmMarketData calldata market, IrmConfiguration calldata irmConfiguration)
        internal
        pure
        returns (uint256, int256)
    {
        // Safe "unchecked" cast because the utilization is smaller than 1 (scaled by WAD).
        int256 utilization =
            int256(market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0);

        int256 errNormFactor = utilization > irmConfiguration.targetUtilization
            ? WAD_INT - irmConfiguration.targetUtilization
            : irmConfiguration.targetUtilization;
        int256 err = (utilization - irmConfiguration.targetUtilization).wDivToZero(errNormFactor);

        int256 startRateAtTarget = market.currentRateAtTarget;

        int256 avgRateAtTarget;
        int256 endRateAtTarget;

        if (startRateAtTarget == 0) {
            // First interaction.
            avgRateAtTarget = irmConfiguration.initialRateAtTarget;
            endRateAtTarget = irmConfiguration.initialRateAtTarget;
        } else {
            // The speed is assumed constant between two updates, but it is in fact not constant because of interest.
            // So the rate is always underestimated.
            int256 speed = irmConfiguration.adjustmentSpeed.wMulToZero(err);
            // market.lastUpdate != 0 because it is not the first interaction with this market.
            // Safe "unchecked" cast because block.timestamp - market.lastUpdate <= block.timestamp <= type(int256).max.
            int256 elapsed = int256(market.elapsedSeconds);
            int256 linearAdaptation = speed * elapsed;

            if (linearAdaptation == 0) {
                // If linearAdaptation == 0, avgRateAtTarget = endRateAtTarget = startRateAtTarget;
                avgRateAtTarget = startRateAtTarget;
                endRateAtTarget = startRateAtTarget;
            } else {
                // Formula of the average rate that should be returned to Morpho Blue:
                // avg = 1/T * ∫_0^T curve(startRateAtTarget*exp(speed*x), err) dx
                // The integral is approximated with the trapezoidal rule:
                // avg ~= 1/T * Σ_i=1^N [curve(f((i-1) * T/N), err) + curve(f(i * T/N), err)] / 2 * T/N
                // Where f(x) = startRateAtTarget*exp(speed*x)
                // avg ~= Σ_i=1^N [curve(f((i-1) * T/N), err) + curve(f(i * T/N), err)] / (2 * N)
                // As curve is linear in its first argument:
                // avg ~= curve([Σ_i=1^N [f((i-1) * T/N) + f(i * T/N)] / (2 * N), err)
                // avg ~= curve([(f(0) + f(T))/2 + Σ_i=1^(N-1) f(i * T/N)] / N, err)
                // avg ~= curve([(startRateAtTarget + endRateAtTarget)/2 + Σ_i=1^(N-1) f(i * T/N)] / N, err)
                // With N = 2:
                // avg ~= curve([(startRateAtTarget + endRateAtTarget)/2 + startRateAtTarget*exp(speed*T/2)] / 2, err)
                // avg ~= curve([startRateAtTarget + endRateAtTarget + 2*startRateAtTarget*exp(speed*T/2)] / 4, err)
                endRateAtTarget = _newRateAtTarget(irmConfiguration, startRateAtTarget, linearAdaptation);
                int256 midRateAtTarget = _newRateAtTarget(irmConfiguration, startRateAtTarget, linearAdaptation / 2);
                avgRateAtTarget = (startRateAtTarget + endRateAtTarget + 2 * midRateAtTarget) / 4;
            }
        }

        // Safe "unchecked" cast because avgRateAtTarget >= 0.
        return (uint256(_curve(irmConfiguration, avgRateAtTarget, err)), endRateAtTarget);
    }

    /// @dev Returns the new rate at target, for a given `startRateAtTarget` and a given `linearAdaptation`.
    /// The formula is: max(min(startRateAtTarget * exp(linearAdaptation), maxRateAtTarget), minRateAtTarget).
    function _newRateAtTarget(
        IrmConfiguration memory irmConfiguration,
        int256 startRateAtTarget,
        int256 linearAdaptation
    ) private pure returns (int256) {
        // Non negative because MIN_RATE_AT_TARGET > 0.
        return startRateAtTarget.wMulToZero(ExpLib.wExp(linearAdaptation)).bound(
            irmConfiguration.minRateAtTarget, irmConfiguration.maxRateAtTarget
        );
    }

    /// @dev Returns the rate for a given `_rateAtTarget` and an `err`.
    /// The formula of the curve is the following:
    /// r = ((1-1/C)*err + 1) * rateAtTarget if err < 0
    ///     ((C-1)*err + 1) * rateAtTarget else.
    function _curve(IrmConfiguration memory irmConfiguration, int256 _rateAtTarget, int256 err)
        private
        pure
        returns (int256)
    {
        // Non negative because 1 - 1/C >= 0, C - 1 >= 0.
        int256 coeff = err < 0
            ? WAD_INT - WAD_INT.wDivToZero(irmConfiguration.curveSteepness)
            : irmConfiguration.curveSteepness - WAD_INT;
        // Non negative if _rateAtTarget >= 0 because if err < 0, coeff <= 1.
        return (coeff.wMulToZero(err) + WAD_INT).wMulToZero(int256(_rateAtTarget));
    }
}
