// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";

/// @dev Singularity Risk params
struct RiskParams {
    uint256 borrowOpeningFee;
    uint256 liquidationMultiplier;
    uint256 minimumTargetUtilization;
    uint256 maximumTargetUtilization;
    uint64 minimumInterestPerSecond;
    uint64 maximumInterestPerSecond;
    uint256 interestElasticity;
    uint256 minLendAmount;
    uint256 exchangeRatePrecision;
    uint256 collateralizationRate;
    uint256 liquidationCollateralizationRate;
    uint256 seedAmount;
    address oracle;
}

/// @notice Contract to create Singularity markets via delegatecall from admin of Penrose
interface ISingularityLauncher {
    error MarketCreationFailed();

    function createSingularity(Singularity._InitMemoryTokensData memory tokensData, RiskParams memory riskParams)
        external
        returns (Singularity);
}
