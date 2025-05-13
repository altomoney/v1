// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MathLib as MathLibMorpho} from "@morpho-blue/libraries/MathLib.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {ExpLib, WAD_INT} from "./libraries/ExpLib.sol";

/// @title Adaptive Curve Interest Rate Model
/// @author Tapioca Foundation
/// @custom:contact security@tapioca.xyz
contract AdaptiveCurveIrm is Ownable, IIrm {
    using MathLibMorpho for uint256;
    //using MathLibMorpho for int256;

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
    constructor(AdaptiveCurveIrmConfig memory _irmConfig, address _owner) {
        // TODO check the input of the config
        irmConfig = _irmConfig;

        _transferOwnership(_owner);
    }

    /// @notice Sets the market address
    /// @param _market The market to set
    /// @dev Used for the first time by the market to set itself to the IRM
    function setMarket(address _market) external {
        if (market != address(0)) revert Alto_IrmMarketAlreadySet();
        market = _market;

        // set the IRM up
        irState.lastUpdate = uint48(block.timestamp);
        (uint256 interest, int256 rateAtTarget) = _computeInterestRate(0, 0);
        irState.rateAtTarget = rateAtTarget;
    }

    /// @notice Sets the borrow rate
    /// @param _irmConfig The new config of the IRM
    /// @dev Reverts on not set market, so the rate has to be set before the market creation.
    function setIrmConfig(AdaptiveCurveIrmConfig memory _irmConfig) external onlyOwner {
        if (market == address(0)) revert Alto_IrmMarketNotSet();
        // TODO check the input of the config

        IMarket(market).accrueInterest();
        irmConfig = _irmConfig;

        // set the IRM up - we don't need to set the lastUpdate because it's already set during accrual
        (uint256 interest, int256 rateAtTarget) =
            _computeInterestRate(IMarket(market).totalSupply().assets, IMarket(market).totalBorrowed().assets);
        irState.rateAtTarget = rateAtTarget;

        emit SetIrmConfig(_irmConfig);
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
        if (msg.sender != market) revert Alto_IrmUnauthorized();

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
        if (market == address(0)) revert Alto_IrmMarketNotSet();

        (uint256 avgRate, int256 rateAtTarget) = _computeInterestRate(_totalSupply, _totalBorrowed);

        uint256 interest = _totalBorrowed.wMulDown(avgRate.wTaylorCompounded(block.timestamp - irState.lastUpdate));

        return (interest, avgRate, rateAtTarget);
    }

    function _updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed)
        internal
        returns (uint256, uint256, int256)
    {
        (uint256 interest, uint256 newBorrowRate, int256 rateAtTarget) = _accrueInterest(_totalSupply, _totalBorrowed);

        irState.lastUpdate = uint48(block.timestamp);
        irState.rateAtTarget = rateAtTarget;

        return (interest, newBorrowRate, rateAtTarget);
    }

    /// @dev from Morpho
    function _computeInterestRate(uint256 _totalSupply, uint256 _totalBorrowed)
        internal
        view
        returns (uint256, int256)
    {
        // Safe "unchecked" cast because the utilization is smaller than 1 (scaled by WAD).
        int256 utilization = int256(_totalSupply > 0 ? _totalBorrowed.wDivDown(_totalSupply) : 0);

        int256 errNormFactor = utilization > irmConfig.targetUtilization
            ? WAD_INT - irmConfig.targetUtilization
            : irmConfig.targetUtilization;
        int256 err = (utilization - irmConfig.targetUtilization).wDivToZero(errNormFactor);

        int256 startRateAtTarget = irState.rateAtTarget;

        int256 avgRateAtTarget;
        int256 endRateAtTarget;

        if (startRateAtTarget == 0) {
            // First interaction.
            avgRateAtTarget = irmConfig.initialRateAtTarget;
            endRateAtTarget = irmConfig.initialRateAtTarget;
        } else {
            // The speed is assumed constant between two updates, but it is in fact not constant because of interest.
            // So the rate is always underestimated.
            int256 speed = irmConfig.adjustmentSpeed.wMulToZero(err);
            // irState.lastUpdate != 0 because it is not the first interaction with this market.
            // Safe "unchecked" cast because block.timestamp - irState.lastUpdate <= block.timestamp <= type(int256).max.
            int256 elapsed = int256(block.timestamp - irState.lastUpdate);
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

        // Safe "unchecked" cast because avgRateAtTarget >= 0.
        return (uint256(_curve(avgRateAtTarget, err)), endRateAtTarget);
    }

    /// @dev from Morpho
    function _curve(int256 _rateAtTarget, int256 err) private pure returns (int256) {
        int256 coeff =
            err < 0 ? WAD_INT - WAD_INT.wDivToZero(irmConfig.curveSteepness) : irmConfig.curveSteepness - WAD_INT;
        return (coeff.wMulToZero(err) + WAD_INT).wMulToZero(int256(_rateAtTarget));
    }

    /// @dev from Morpho
    function _newRateAtTarget(int256 startRateAtTarget, int256 linearAdaptation) private pure returns (int256) {
        return startRateAtTarget.wMulToZero(ExpLib.wExp(linearAdaptation)).bound(
            irmConfig.minRateAtTarget, irmConfig.maxRateAtTarget
        );
    }
}
