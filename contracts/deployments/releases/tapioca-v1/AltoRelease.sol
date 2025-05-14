// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TapiocaUtilitiesBatch} from "./batches/TapiocaUtilitiesBatch.sol";
import {TapiocaUsdoBatch} from "./batches/TapiocaUsdoBatch.sol";
import {AltoMarketsBatch} from "./batches/AltoMarketsBatch.sol";
import {TapiocaPostSetup} from "./batches/TapiocaPostSetup.sol";

import "../../interfaces/IAltoReport.sol";
import "forge-std/console.sol";

/// @title AltoRelease
/// @dev To be imported by Foundry scripts to deploy Tapioca V1.
library AltoRelease {
    /// @notice Deploy TapiocaV1 following input parameters and previous deployment report
    /// @dev Main entry point for deployment of Tapioca V1
    function deployAltoV1(TapiocaInput memory input, AltoReport memory prevReport)
        internal
        returns (AltoReport memory)
    {
        Reports memory reports;
        TapiocaPostSetup postSetupBatch = new TapiocaPostSetup();

        TapiocaUtilitiesBatch utilitiesBatch;
        (utilitiesBatch, reports.utilitiesReport) = _deployUtilities(
            address(postSetupBatch), input.zeroXProxy, input.lzChainId, input.isTestnet, input.wrappedNativeToken
        );

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
            reports.utilitiesReport.tapiocaMulticall,
            reports.usdoReport.usdo,
            reports.lendingReport.borrowMarket,
            reports.lendingReport.mintMarket,
            reports.utilitiesReport.multiTokenSender,
            reports.utilitiesReport.altoLeverage
        );

        return _generateMarketReport(reports);
    }

    function _deployUtilities(
        address owner,
        address zeroXSwapper,
        uint16 lzChainId,
        bool isTestnet,
        address wrappedNativeToken
    ) private returns (TapiocaUtilitiesBatch utilitiesBatch, UtilitiesReport memory report) {
        utilitiesBatch = new TapiocaUtilitiesBatch(owner, zeroXSwapper, lzChainId, isTestnet, wrappedNativeToken);

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
        TapiocaUsdoBatch usdoBatch = new TapiocaUsdoBatch(endpoint, delegate);
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

        report.tapiocaMulticall = reports.utilitiesReport.tapiocaMulticall;
        report.multiTokenSender = reports.utilitiesReport.multiTokenSender;
        report.zeroXSwapper = reports.utilitiesReport.zeroXSwapper;

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
