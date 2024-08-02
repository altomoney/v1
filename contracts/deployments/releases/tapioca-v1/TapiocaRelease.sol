// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {TapiocaMagnetarBatchOne} from "./batches/TapiocaMagnetarBatchOne.sol";
import {TapiocaMagnetarBatchTwo} from "./batches/TapiocaMagnetarBatchTwo.sol";
import {TapiocaUtilitiesBatch} from "./batches/TapiocaUtilitiesBatch.sol";
import {TapiocaYieldboxBatch} from "./batches/TapiocaYieldboxBatch.sol";
import "../../interfaces/ITapiocaReport.sol";

/// @title TapiocaRelease
/// @dev To be imported by Foundry scripts to deploy Tapioca V1.
library TapiocaRelease {
    /// @notice Deploy TapiocaV1 following input parameters and previous deployment report
    /// @dev Main entry point for deployment of Tapioca V1
    function deployTapiocaV1(TapiocaInput memory input, TapiocaReport memory prevReport)
        internal
        returns (TapiocaReport memory)
    {
        UtilitiesReport memory utilitiesReport = _deployUtilities(input.owner, input.zeroXSwapper, input.lzChainId);

        YieldboxReport memory yieldboxReport =
            _deployYieldBox(input.owner, input.wrappedNativeToken, utilitiesReport.pearlmit);

        MagnetarDepsReport memory magnetarDepsReport =
            _deployMagnetarDeps(utilitiesReport.pearlmit, utilitiesReport.toeHelper);

        MagnetarReport memory magnetarReport = _deployMagnetar(
            input.owner,
            utilitiesReport.cluster,
            utilitiesReport.pearlmit,
            utilitiesReport.toeHelper,
            magnetarDepsReport
        );

        return _generateMarketReport(utilitiesReport, yieldboxReport, magnetarDepsReport, magnetarReport);
    }

    ///
    /// Internal functions for deployment of batch contracts and retrieval of deployment report
    ///

    function _deployMagnetarDeps(address pearlmit, address toeHelper)
        private
        returns (MagnetarDepsReport memory report)
    {
        TapiocaMagnetarBatchOne magnetarDepsBatch = new TapiocaMagnetarBatchOne(pearlmit, toeHelper);
        return magnetarDepsBatch.getMagnetarDepsReport();
    }

    function _deployMagnetar(
        address owner,
        address cluster,
        address pearlmit,
        address toeHelper,
        MagnetarDepsReport memory deps
    ) private returns (MagnetarReport memory report) {
        TapiocaMagnetarBatchTwo magnetarBatchTwo =
            new TapiocaMagnetarBatchTwo(owner, cluster, pearlmit, toeHelper, deps);
        return magnetarBatchTwo.getMagnetarReport();
    }

    function _deployUtilities(address owner, address zeroXSwapper, uint16 lzChainId)
        private
        returns (UtilitiesReport memory report)
    {
        TapiocaUtilitiesBatch utilitiesBatch = new TapiocaUtilitiesBatch(owner, zeroXSwapper, lzChainId, false);
        return utilitiesBatch.getUtilitiesReport();
    }

    function _deployYieldBox(address owner, address wrappedNativeToken, address pearlmit)
        private
        returns (YieldboxReport memory report)
    {
        TapiocaYieldboxBatch yieldboxBatch = new TapiocaYieldboxBatch(owner, wrappedNativeToken, pearlmit);
        return yieldboxBatch.getYieldboxReport();
    }

    function _generateMarketReport(
        UtilitiesReport memory utilitiesReport,
        YieldboxReport memory yieldboxReport,
        MagnetarDepsReport memory magnetarDepsReport,
        MagnetarReport memory magnetarReport
    ) private pure returns (TapiocaReport memory) {
        TapiocaReport memory report;

        report.cluster = utilitiesReport.cluster;
        report.pearlmit = utilitiesReport.pearlmit;
        report.tapiocaMulticall = utilitiesReport.tapiocaMulticall;
        report.toeHelper = utilitiesReport.toeHelper;

        report.yieldbox = yieldboxReport.yieldbox;
        report.yieldboxUri = yieldboxReport.yieldboxUri;

        report.magnetarCollateralModule = magnetarDepsReport.magnetarCollateralModule;
        report.magnetarMintModule = magnetarDepsReport.magnetarMintModule;
        report.magnetarOptionModule = magnetarDepsReport.magnetarOptionModule;
        report.magnetarYieldboxModule = magnetarDepsReport.magnetarYieldboxModule;

        report.magnetar = magnetarReport.magnetar;
        report.magnetarHelper = magnetarReport.magnetarHelper;

        return report;
    }
}
