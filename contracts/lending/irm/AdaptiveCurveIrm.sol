// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MathLib as MathLibInt, WAD_INT} from "@morpho-org/irm/adaptive-curve-irm/libraries/MathLib.sol";
import {UtilsLib} from "@morpho-org/irm/adaptive-curve-irm/libraries/UtilsLib.sol";
import {MathLib} from "@morpho-org/irm/adaptive-curve-irm/libraries/MathLib.sol";

import {IIrm} from "../interfaces/IIrm.sol";
import {IMarket} from "../interfaces/IMarket.sol";
import {ExpLib} from "../libraries/ExpLib.sol";
import {FixedPointMath} from "../libraries/FixedPointMath.sol";

/// @title Adaptive Curve Interest Rate Model
/// @author Alto Foundation
/// @author Adapted from Morpho Labs (https://github.com/morpho-org/morpho-blue-irm/).
/// @author Inspired by Euler's (https://github.com/euler-xyz/evk-periphery) implementation.
/// @custom:contact security@alto.xyz
/// @notice A Adaptive Curve IRM that adjusts the rate at target utilization based on time spent above/below it.
/// @dev This implementation intentionally leaves variables names, units and ExpLib unchanged from original.
/// @dev This IRM has adjustable parameters post deployment.
contract AdaptiveCurveIrm is Ownable, IIrm {
    using FixedPointMath for uint256;
    using MathLib for uint256;
    using UtilsLib for int256;
    using MathLibInt for int256;

    int256 internal constant YEAR = int256(365 days);

    /// @notice The config of the Adaptive Curve IRM
    struct AdaptiveCurveIrmConfig {
        int256 curveSteepness;
        int256 adjustmentSpeed;
        int256 targetUtilization;
        int256 initialRateAtTarget;
        int256 minRateAtTarget;
        int256 maxRateAtTarget;
    }

    /// @notice Internal cached state of the interest rate model.
    struct IRState {
        /// @dev The rate at target of the last update.
        int256 rateAtTarget;
        /// @dev The timestamp of the last update to the model.
        uint48 lastUpdate;
    }

    event SetIrmConfig(AdaptiveCurveIrmConfig irmConfig);

    AdaptiveCurveIrmConfig public irmConfig;
    IRState public irState;
    address public market;

    /// @notice Constructor
    /// @param _irmConfig The config of the IRM
    /// @param _owner The owner of the IRM - shouldn't be market
    constructor(AdaptiveCurveIrmConfig memory _irmConfig, address _owner) Ownable(_owner) {
        _validateConfig(_irmConfig);
        irmConfig = _irmConfig;
    }

    /// @notice Sets the market address
    /// @param _market The market to set
    /// @dev Used for the first time by the market to set itself to the IRM
    function setMarket(address _market) external {
        if (market != address(0)) revert IrmMarketAlreadySet();
        market = _market;

        // set the IRM up
        irState.lastUpdate = uint48(block.timestamp);
        (, int256 rateAtTarget) = _computeInterestRate(0, 0);
        irState.rateAtTarget = rateAtTarget;
    }

    /// @notice Sets the borrow rate
    /// @param _irmConfig The new config of the IRM
    /// @dev Reverts on not set market, so the rate has to be set before the market creation.
    function setIrmConfig(AdaptiveCurveIrmConfig memory _irmConfig) external onlyOwner {
        if (market == address(0)) revert IrmMarketNotSet();

        IMarket(market).accrueInterest();

        _validateConfig(_irmConfig);
        irmConfig = _irmConfig;

        // set the IRM up - we don't need to set the lastUpdate because it's already set during accrual
        irState = IRState({rateAtTarget: 0, lastUpdate: irState.lastUpdate});
        (, int256 rateAtTarget) = _computeInterestRate(0, 0);
        irState = IRState({rateAtTarget: rateAtTarget, lastUpdate: irState.lastUpdate});

        emit SetIrmConfig(_irmConfig);
    }

    function _validateConfig(AdaptiveCurveIrmConfig memory _irmConfig) internal pure {
        if (_irmConfig.curveSteepness < 1.01e18 || _irmConfig.curveSteepness > 100e18) {
            revert IrmInvalidParams();
        }
        if (_irmConfig.adjustmentSpeed < 2e18 / YEAR || _irmConfig.adjustmentSpeed > 1000e18 / YEAR) {
            revert IrmInvalidParams();
        }
        if (_irmConfig.targetUtilization <= 0 || _irmConfig.targetUtilization > 1e18) {
            revert IrmInvalidParams();
        }
        if (
            _irmConfig.initialRateAtTarget < _irmConfig.minRateAtTarget
                || _irmConfig.initialRateAtTarget > _irmConfig.maxRateAtTarget
        ) {
            revert IrmInvalidParams();
        }
        if (_irmConfig.minRateAtTarget < 0.001e18 / YEAR || _irmConfig.minRateAtTarget > 10e18 / YEAR) {
            revert IrmInvalidParams();
        }
        if (_irmConfig.maxRateAtTarget < 0.001e18 / YEAR || _irmConfig.maxRateAtTarget > 10e18 / YEAR) {
            revert IrmInvalidParams();
        }
    }

    /// @inheritdoc IIrm
    function updateInterestRateView(uint256 _totalSupply, uint256 _totalBorrowed)
        external
        view
        returns (uint256, uint256)
    {
        (uint256 interest, uint256 newBorrowRate, int256 rateAtTarget) = _accrueInterest(_totalSupply, _totalBorrowed);

        return (interest, newBorrowRate);
    }

    /// @inheritdoc IIrm
    function updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed) external returns (uint256, uint256) {
        if (msg.sender != market) revert IrmUnauthorized();

        (uint256 interest, uint256 newBorrowRate, int256 rateAtTarget) =
            _updateInterestRate(_totalSupply, _totalBorrowed);

        return (interest, newBorrowRate);
    }

    function _accrueInterest(uint256 _totalSupply, uint256 _totalBorrowed)
        internal
        view
        returns (uint256, uint256, int256)
    {
        // If the market is not set, the lastUpdate is not set, so we revert.
        if (market == address(0)) revert IrmMarketNotSet();

        (uint256 avgRate, int256 rateAtTarget) = _computeInterestRate(_totalSupply, _totalBorrowed);

        uint256 interest =
            _totalBorrowed.multiplyWithPrecision(avgRate.calculateCompoundInterest(_getCurrentTimeElapsed()));

        return (interest, avgRate, rateAtTarget);
    }

    function _updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed)
        internal
        returns (uint256, uint256, int256)
    {
        (uint256 interest, uint256 newBorrowRate, int256 rateAtTarget) = _accrueInterest(_totalSupply, _totalBorrowed);

        irState = IRState({rateAtTarget: rateAtTarget, lastUpdate: uint48(block.timestamp)});

        return (interest, newBorrowRate, rateAtTarget);
    }

    function _getCurrentTimeElapsed() internal view virtual returns (uint256) {
        return block.timestamp - irState.lastUpdate;
    }

    /// @dev from Morpho
    function _computeInterestRate(uint256 _totalSupply, uint256 _totalBorrowed)
        internal
        view
        returns (uint256, int256)
    {
        int256 utilization = int256(_totalSupply > 0 ? _totalBorrowed.divideWithPrecisionDown(_totalSupply) : 0);

        int256 errNormFactor = utilization > irmConfig.targetUtilization
            ? WAD_INT - irmConfig.targetUtilization
            : irmConfig.targetUtilization;
        int256 err = (utilization - irmConfig.targetUtilization).wDivToZero(errNormFactor);

        int256 startRateAtTarget = irState.rateAtTarget;

        int256 avgRateAtTarget;
        int256 endRateAtTarget;

        if (startRateAtTarget == 0) {
            avgRateAtTarget = irmConfig.initialRateAtTarget;
            endRateAtTarget = irmConfig.initialRateAtTarget;
        } else {
            int256 speed = irmConfig.adjustmentSpeed.wMulToZero(err);
            // following is the only change from the original implementation - _getCurrentTimeElapsed is used for testing
            int256 elapsed = int256(_getCurrentTimeElapsed());
            int256 linearAdaptation = speed * elapsed;

            if (linearAdaptation == 0) {
                avgRateAtTarget = startRateAtTarget;
                endRateAtTarget = startRateAtTarget;
            } else {
                endRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation);
                int256 midRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation / 2);
                avgRateAtTarget = (startRateAtTarget + endRateAtTarget + 2 * midRateAtTarget) / 4;
            }
        }

        return (uint256(_curve(avgRateAtTarget, err)), endRateAtTarget);
    }

    /// @dev from Morpho
    function _curve(int256 _rateAtTarget, int256 err) private view returns (int256) {
        int256 coeff =
            err < 0 ? WAD_INT - WAD_INT.wDivToZero(irmConfig.curveSteepness) : irmConfig.curveSteepness - WAD_INT;
        return (coeff.wMulToZero(err) + WAD_INT).wMulToZero(int256(_rateAtTarget));
    }

    /// @dev from Morpho
    function _newRateAtTarget(int256 startRateAtTarget, int256 linearAdaptation) private view returns (int256) {
        return startRateAtTarget.wMulToZero(ExpLib.wExp(linearAdaptation)).bound(
            irmConfig.minRateAtTarget, irmConfig.maxRateAtTarget
        );
    }
}
