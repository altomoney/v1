// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {LendingProcedure} from "../../../procedures/LendingProcedure.sol";
import {LendingReport} from "../../../interfaces/IAltoReport.sol";
import {RiskParams, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

/// @title AltoMarketsBatch
/// @notice Deploy Alto markets
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract AltoMarketsBatchTwo is LendingProcedure {
    LendingReport internal _lendingReport;

    constructor(
        address usdo,
        address delegate,
        address collateralTokenMintMarket,
        address mintIrm,
        address mintOracle,
        bool shouldUseSafeProxy,
        LendingReport memory lendingReport
    ) {
        _lendingReport = lendingReport;

        RiskParams memory mintRiskParams = RiskParams({
            borrowToken: usdo,
            collateralToken: collateralTokenMintMarket,
            irm: mintIrm,
            owner: delegate,
            oracle: mintOracle,
            maxLtv: 0.75 ether,
            debtCeiling: 0,
            feeRecipient: delegate,
            borrowOpeningFee: 0
        });
        LiquidationConfiguration memory mintLiquidationConfiguration = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        _lendingReport.mintMarket = _deployMintMarket(mintRiskParams, mintLiquidationConfiguration, shouldUseSafeProxy);
    }

    function getLendingReport() external view returns (LendingReport memory) {
        return _lendingReport;
    }
}
