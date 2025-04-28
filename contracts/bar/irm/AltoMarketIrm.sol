// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoAdaptiveCurveIrm} from "./AltoAdaptiveCurveIrm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoAdaptiveCurveIrm, IrmMarketData, IrmConfiguration} from "./IAltoAdaptiveCurveIrm.sol";

/// @title AltoMarketIrm
/// @author Alto Labs
/// @custom:contact security@alto.money
abstract contract AltoMarketIrm is Ownable {
    uint128 public irmLastUpdateTimestamp;
    int256 public irmCurrentRateAtTarget;
    IrmConfiguration public irmConfiguration;
    uint256 public irmInterestFee; // TODO Should I inject it by constructor and add a setter (or immutable)?

    event IrmConfigurationUpdated(IrmConfiguration newIrmConfiguration);
    event BorrowRateUpdated(uint256 borrowRate, int256 endRateAtTarget);

    constructor(IrmConfiguration memory _irmConfiguration) {
        irmLastUpdateTimestamp = uint128(block.timestamp);
        irmConfiguration = _irmConfiguration;
        accrueInterest(0, 0);
    }

    function accrueMarket(uint256 interest, uint256 feeAmount, uint256 borrowRate) public virtual;

    function getIrm() public view virtual returns (address);

    function setIrmConfiguration(IrmConfiguration calldata _irmConfiguration) external onlyOwner {        
        if (_irmConfiguration.curveSteepness != type(int256).max) {
            irmConfiguration.curveSteepness = _irmConfiguration.curveSteepness;
        }
        if (_irmConfiguration.adjustmentSpeed != type(int256).max) {
            irmConfiguration.adjustmentSpeed = _irmConfiguration.adjustmentSpeed;
        }
        if (_irmConfiguration.targetUtilization != type(int256).max) {
            irmConfiguration.targetUtilization = _irmConfiguration.targetUtilization;
        }
        if (_irmConfiguration.initialRateAtTarget != type(int256).max) {
            irmConfiguration.initialRateAtTarget = _irmConfiguration.initialRateAtTarget;
        }
        if (_irmConfiguration.minRateAtTarget != type(int256).max) {
            irmConfiguration.minRateAtTarget = _irmConfiguration.minRateAtTarget;
        }
        if (_irmConfiguration.maxRateAtTarget != type(int256).max) {
            irmConfiguration.maxRateAtTarget = _irmConfiguration.maxRateAtTarget;
        }

        emit IrmConfigurationUpdated(_irmConfiguration);
        accrueInterest(0, 0);
    }

    function accrueInterest(uint256 _totalSupplyAssets, uint256 _totalBorrowAssets) public {
        if (block.timestamp > irmLastUpdateTimestamp) {
            IAltoAdaptiveCurveIrm irm = IAltoAdaptiveCurveIrm(getIrm());
            uint256 elapsedSeconds = block.timestamp - irmLastUpdateTimestamp;
            IrmMarketData memory market = IrmMarketData({
                totalSupplyAssets: _totalSupplyAssets,
                totalBorrowAssets: _totalBorrowAssets,
                elapsedSeconds: elapsedSeconds,
                currentRateAtTarget: irmCurrentRateAtTarget
            });

            (uint256 interest, uint256 feeAmount, uint256 avgRate, int256 endRateAtTarget) =
                irm.getAccruedInterest(market, irmConfiguration, irmInterestFee);

            accrueMarket(interest, feeAmount, avgRate);
            irmCurrentRateAtTarget = endRateAtTarget;
            irmLastUpdateTimestamp = uint128(block.timestamp);
            emit BorrowRateUpdated(avgRate, endRateAtTarget);
        }
    }
}
