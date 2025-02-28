// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";

/// @dev BigBang Risk params
struct BigBangRiskParams {
    uint256 debtRateAgainstEth;
    uint256 debtRateMin;
    uint256 debtRateMax;
    uint256 seedAmount;
    uint256 exchangeRatePrecision;
    uint256 collateralizationRate;
    uint256 liquidationCollateralizationRate;
    address collateral;
    address oracle;
    bool isEthMarket;
}

/// @notice Contract to create Singularity markets via delegatecall from admin of Penrose
interface IBigBangLauncher {
    error MarketCreationFailed();

    function createBigBang(BigBangRiskParams memory riskParams) external returns (BigBang);
}
