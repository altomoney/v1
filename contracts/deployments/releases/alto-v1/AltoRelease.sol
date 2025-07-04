// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoUtilitiesBatch} from "./batches/AltoUtilitiesBatch.sol";
import {AltoUsdoBatch} from "./batches/AltoUsdoBatch.sol";
import {AltoMarketsBatchOne} from "./batches/AltoMarketsBatchOne.sol";
import {AltoMarketsBatchTwo} from "./batches/AltoMarketsBatchTwo.sol";
import {AltoPostSetup} from "./batches/AltoPostSetup.sol";
import {AltoTokenRewardsBatch} from "./batches/AltoTokenRewardsBatch.sol";

import {
    AltoInput,
    AltoReport,
    AltoTokenReport,
    UtilitiesReport,
    UsdoReport,
    LendingReport,
    Reports
} from "../../interfaces/IAltoReport.sol";
import "forge-std/console.sol";

/// @title AltoRelease
/// @dev To be imported by Foundry scripts to deploy Alto V1.
library AltoRelease {
    /// @notice Deploy Alto V1 following input parameters and previous deployment report
    /// @dev Main entry point for deployment of Alto V1
    function deployAltoV1(AltoInput memory input, AltoReport memory prevReport) internal returns (AltoReport memory) {
        Reports memory reports;
        AltoPostSetup postSetupBatch = new AltoPostSetup();

        AltoUtilitiesBatch utilitiesBatch;
        (utilitiesBatch, reports.utilitiesReport) =
            _deployUtilities(address(postSetupBatch), input.lzChainId, input.isTestnet, input.wrappedNativeToken);

        (reports.usdoReport, reports.lendingReport) = _deployUsdoAndMarkets(
            input.lzEndpoint,
            address(postSetupBatch), // delegate
            input.collateralTokenBorrowMarket,
            input.collateralTokenMintMarket,
            reports.utilitiesReport.borrowIrm,
            input.borrowOracle,
            reports.utilitiesReport.mintIrm,
            input.mintOracle,
            input.shouldUseSafeProxy
        );

        AltoTokenRewardsBatch tokenRewardsBatch = new AltoTokenRewardsBatch(input.altoToken, address(postSetupBatch));
        reports.altoTokenReport = tokenRewardsBatch.getAltoTokenReport();

        postSetupBatch.postSetup(
            reports.utilitiesReport.altoMulticall,
            reports.usdoReport.usdo,
            reports.lendingReport.borrowMarket,
            reports.lendingReport.mintMarket,
            reports.utilitiesReport.multiTokenSender,
            reports.utilitiesReport.altoLeverage,
            reports.utilitiesReport.leverageSwapper
        );

        return _generateMarketReport(reports);
    }

    function _deployUtilities(address owner, uint16 lzChainId, bool isTestnet, address wrappedNativeToken)
        private
        returns (AltoUtilitiesBatch utilitiesBatch, UtilitiesReport memory report)
    {
        utilitiesBatch = new AltoUtilitiesBatch(owner, lzChainId, isTestnet, wrappedNativeToken);

        return (utilitiesBatch, utilitiesBatch.getUtilitiesReport());
    }

    function _deployUsdoAndMarkets(
        address endpoint,
        address delegate,
        address collateralTokenBorrowMarket,
        address collateralTokenMintMarket,
        address borrowIrm,
        address borrowOracle,
        address mintIrm,
        address mintOracle,
        bool shouldUseSafeProxy
    ) private returns (UsdoReport memory usdoReport, LendingReport memory lendingReport) {
        AltoUsdoBatch usdoBatch = new AltoUsdoBatch(endpoint, delegate);
        usdoReport = usdoBatch.getUsdoReport();

        AltoMarketsBatchOne marketsBatchOne = new AltoMarketsBatchOne(
            usdoReport.usdo, delegate, collateralTokenBorrowMarket, borrowIrm, borrowOracle, shouldUseSafeProxy
        );
        LendingReport memory lendingReportOne = marketsBatchOne.getLendingReport();

        AltoMarketsBatchTwo marketsBatchTwo = new AltoMarketsBatchTwo(
            usdoReport.usdo,
            delegate,
            collateralTokenMintMarket,
            mintIrm,
            mintOracle,
            shouldUseSafeProxy,
            lendingReportOne
        );
        lendingReport = marketsBatchTwo.getLendingReport();

        return (usdoReport, lendingReport);
    }

    function _deployAltoToken(address altoToken, address admin) private returns (AltoTokenReport memory tokenReport) {
        AltoTokenRewardsBatch tokenRewardsBatch = new AltoTokenRewardsBatch(altoToken, admin);
        tokenReport = tokenRewardsBatch.getAltoTokenReport();

        return tokenReport;
    }

    function _generateMarketReport(Reports memory reports) private pure returns (AltoReport memory) {
        AltoReport memory report;

        report.altoMulticall = reports.utilitiesReport.altoMulticall;
        report.multiTokenSender = reports.utilitiesReport.multiTokenSender;
        report.leverageSwapper = reports.utilitiesReport.leverageSwapper;

        report.usdo = reports.usdoReport.usdo;

        report.borrowMarket = reports.lendingReport.borrowMarket;
        report.borrowIrm = reports.utilitiesReport.borrowIrm;
        report.mintMarket = reports.lendingReport.mintMarket;
        report.mintIrm = reports.utilitiesReport.mintIrm;
        report.bundler3 = reports.utilitiesReport.bundler3;
        report.altoAdapter = reports.utilitiesReport.altoAdapter;
        report.altoLeverage = reports.utilitiesReport.altoLeverage;
        report.rewardsDistributor = reports.altoTokenReport.rewardsDistributor;
        report.twAltoStaking = reports.altoTokenReport.twAltoStaking;

        return report;
    }
}
