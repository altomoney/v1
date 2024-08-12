// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {TapiocaMagnetarBatchOne} from "./batches/TapiocaMagnetarBatchOne.sol";
import {TapiocaMagnetarBatchTwo} from "./batches/TapiocaMagnetarBatchTwo.sol";
import {TapiocaUtilitiesBatch} from "./batches/TapiocaUtilitiesBatch.sol";
import {TapiocaYieldboxBatch} from "./batches/TapiocaYieldboxBatch.sol";
import {TapiocaUsdoBatchOne} from "./batches/TapiocaUsdoBatchOne.sol";
import {TapiocaUsdoBatchTwo} from "./batches/TapiocaUsdoBatchTwo.sol";
import {TapiocaUsdoBatchThree} from "./batches/TapiocaUsdoBatchThree.sol";
import {TapiocaSingularityBatch1} from "./batches/TapiocaSingularityBatch1.sol";
import {TapiocaSingularityBatch2} from "./batches/TapiocaSingularityBatch2.sol";
import {TapiocaSingularityBatch3} from "./batches/TapiocaSingularityBatch3.sol";

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
        UtilitiesReport memory utilitiesReport =
            _deployUtilities(input.owner, input.zeroXSwapper, input.lzChainId, input.wrappedNativeToken);

        YieldboxReport memory yieldboxReport =
            _deployYieldBox(input.owner, input.wrappedNativeToken, utilitiesReport.pearlmit);

        MagnetarDepsReport memory magnetarDepsReport =
            _deployMagnetarDeps(utilitiesReport.pearlmit, utilitiesReport.toeHelper);

        MagnetarReport memory magnetarReport = _deployMagnetar(
            input.owner,
            utilitiesReport.cluster,
            utilitiesReport.pearlmit,
            utilitiesReport.toeHelper,
            input.zeroXSwapper,
            input.wrappedNativeToken,
            magnetarDepsReport
        );

        (
            UsdoModulesReport memory modulesReport,
            UsdoMarketModulesReport memory marketModulesReport,
            UsdoReport memory usdoReport
        ) = _deployUSDO(
            input.lzEndpoint,
            input.owner, // delegate
            yieldboxReport.yieldbox,
            utilitiesReport.cluster,
            yieldboxReport.extExec,
            utilitiesReport.pearlmit
        );

        return _generateMarketReport(
            utilitiesReport,
            yieldboxReport,
            magnetarDepsReport,
            magnetarReport,
            modulesReport,
            marketModulesReport,
            usdoReport
        );
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
        address zeroXSwapper,
        address wrappedNativeToken,
        MagnetarDepsReport memory deps
    ) private returns (MagnetarReport memory report) {
        TapiocaMagnetarBatchTwo magnetarBatchTwo =
            new TapiocaMagnetarBatchTwo(owner, cluster, pearlmit, toeHelper, zeroXSwapper, wrappedNativeToken, deps);
        return magnetarBatchTwo.getMagnetarReport();
    }

    function _deployUtilities(address owner, address zeroXSwapper, uint16 lzChainId, address wrappedNativeToken)
        private
        returns (UtilitiesReport memory report)
    {
        TapiocaUtilitiesBatch utilitiesBatch =
            new TapiocaUtilitiesBatch(owner, zeroXSwapper, wrappedNativeToken, lzChainId, false);
        return utilitiesBatch.getUtilitiesReport();
    }

    function _deployYieldBox(address owner, address wrappedNativeToken, address pearlmit)
        private
        returns (YieldboxReport memory report)
    {
        TapiocaYieldboxBatch yieldboxBatch = new TapiocaYieldboxBatch(owner, wrappedNativeToken, pearlmit);
        return yieldboxBatch.getYieldboxReport();
    }

    function _deployUSDO(
        address endpoint,
        address delegate,
        address yieldbox,
        address cluster,
        address extExec,
        address pearlmit
    )
        private
        returns (
            UsdoModulesReport memory modulesReport,
            UsdoMarketModulesReport memory marketModulesReport,
            UsdoReport memory usdoReport
        )
    {
        TapiocaUsdoBatchOne usdoBatchOne =
            new TapiocaUsdoBatchOne(endpoint, delegate, yieldbox, cluster, extExec, pearlmit);
        modulesReport = usdoBatchOne.getUsdoModulesReport();

        TapiocaUsdoBatchTwo usdoBatchTwo =
            new TapiocaUsdoBatchTwo(endpoint, delegate, yieldbox, cluster, extExec, pearlmit);
        marketModulesReport = usdoBatchTwo.getUsdoMarketModulesReport();
        TapiocaUsdoBatchThree usdoBatchThree = new TapiocaUsdoBatchThree(
            endpoint,
            delegate,
            yieldbox,
            cluster,
            extExec,
            pearlmit,
            modulesReport.usdoSenderModule,
            modulesReport.usdoReceiverModule,
            marketModulesReport.marketReceiverModule,
            marketModulesReport.optionReceiverModule
        );
        usdoReport = usdoBatchThree.getUsdoReport();
        return (modulesReport, marketModulesReport, usdoReport);
    }

    function _generateMarketReport(
        UtilitiesReport memory utilitiesReport,
        YieldboxReport memory yieldboxReport,
        MagnetarDepsReport memory magnetarDepsReport,
        MagnetarReport memory magnetarReport,
        UsdoModulesReport memory modulesReport,
        UsdoMarketModulesReport memory marketModulesReport,
        UsdoReport memory usdoReport
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
        report.liquidatorReceiver = yieldboxReport.liquidatorReceiver;
        report.extExec = yieldboxReport.extExec;
        report.usdoSenderModule = modulesReport.usdoSenderModule;
        report.usdoReceiverModule = modulesReport.usdoReceiverModule;
        report.marketReceiverModule = marketModulesReport.marketReceiverModule;
        report.optionReceiverModule = marketModulesReport.optionReceiverModule;
        report.usdo = usdoReport.usdo;

        return report;
    }
}
