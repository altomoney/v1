// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoUtilitiesBatch} from "./batches/AltoUtilitiesBatch.sol";
import {AltoUsdoBatch} from "./batches/AltoUsdoBatch.sol";
import {AltoMarketsBatch} from "./batches/AltoMarketsBatch.sol";
import {AltoPostSetup} from "./batches/AltoPostSetup.sol";

import {
    AltoInput,
    AltoReport,
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
            input.mintOracle
        );

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
        address mintOracle
    ) private returns (UsdoReport memory usdoReport, LendingReport memory lendingReport) {
        AltoUsdoBatch usdoBatch = new AltoUsdoBatch(endpoint, delegate);
        usdoReport = usdoBatch.getUsdoReport();

        AltoMarketsBatch marketsBatch = new AltoMarketsBatch(
            usdoReport.usdo,
            delegate,
            collateralTokenBorrowMarket,
            collateralTokenMintMarket,
            borrowIrm,
            borrowOracle,
            mintIrm,
            mintOracle
        );
        lendingReport = marketsBatch.getLendingReport();
        return (usdoReport, lendingReport);
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

        return report;
    }
}
