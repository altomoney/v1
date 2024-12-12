// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

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
import {TapiocaPenroseBatch} from "./batches/TapiocaPenroseBatch.sol";
import {TapiocaBBBatch1} from "./batches/TapiocaBBBatch1.sol";
import {TapiocaBBBatch2} from "./batches/TapiocaBBBatch2.sol";
import {TapiocaBBBatch3} from "./batches/TapiocaBBBatch3.sol";
import {TapiocaTOFTModulesBatchOne} from "./batches/TapiocaTOFTModulesBatchOne.sol";
import {TapiocaTOFTModulesBatchTwo} from "./batches/TapiocaTOFTModulesBatchTwo.sol";
import {TapiocaTOFTMetaModulesBatchTwo} from "./batches/TapiocaTOFTMetaModulesBatchTwo.sol";
import {TapiocaTOFTModulesBatchThree} from "./batches/TapiocaTOFTModulesBatchThree.sol";

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
        Reports memory reports;
        TapiocaUtilitiesBatch utilitiesBatch;
        (utilitiesBatch, reports.utilitiesReport) = _deployUtilities(input.owner, input.zeroXSwapper, input.lzChainId);

        reports.ExtExReport = _deployYieldBox(
            input.owner,
            input.wrappedNativeToken,
            reports.utilitiesReport.pearlmit,
            reports.utilitiesReport.cluster,
            input.zeroXSwapper
        );

        reports.magnetarDepsReport =
            _deployMagnetarDeps(reports.utilitiesReport.pearlmit, reports.utilitiesReport.toeHelper);

        reports.magnetarReport = _deployMagnetar(
            input.owner,
            reports.utilitiesReport.cluster,
            reports.utilitiesReport.pearlmit,
            reports.utilitiesReport.toeHelper,
            input.zeroXSwapper,
            input.wrappedNativeToken,
            reports.magnetarDepsReport
        );

        (reports.usdoModulesReport, reports.usdoMarketModulesReport, reports.usdoReport) = _deployUSDO(
            input.lzEndpoint,
            input.owner, // delegate
            reports.ExtExReport.yieldbox,
            reports.utilitiesReport.cluster,
            reports.ExtExReport.extExec,
            reports.utilitiesReport.pearlmit
        );

        reports.sglReport = _deploySingularity();

        reports.bbReport =
            _deployBigBangModules(input.lzEndpoint, input.lzChainId, reports.utilitiesReport.tapiocaMulticall);
        reports.penroseReport = _deployPenrose(
            reports.ExtExReport.yieldbox,
            reports.utilitiesReport.cluster,
            input.tapToken,
            reports.usdoReport.usdo,
            input.wrappedNativeToken,
            reports.utilitiesReport.pearlmit,
            input.owner,
            reports.sglReport.singularity,
            reports.bbReport.bigbang,
            prevReport.penrose
        );

        utilitiesBatch.initializeCluster(
            reports.utilitiesReport.cluster,
            reports.utilitiesReport.zeroXSwapper,
            reports.ExtExReport.yieldbox,
            reports.magnetarReport.magnetar,
            reports.penroseReport.penrose,
            reports.utilitiesReport.pauser,
            reports.utilitiesReport.tapiocaMulticall
        );

        reports.toftModulesReport = _deployTOFTModules(
            input.lzEndpoint, input.lzChainId, reports.utilitiesReport.tapiocaMulticall, input.isMetaInstance
        );

        return _generateMarketReport(reports);
    }

    ///
    /// Internal functions for deployment of batch contracts and retrieval of deployment report
    ///

    function _deployMagnetarDeps(address pearlmit, address toeHelper)
        private
        returns (MagnetarDepsReport memory report)
    {
        TapiocaMagnetarBatchOne magnetarDepsBatch = new TapiocaMagnetarBatchOne(toeHelper);
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

    function _deployUtilities(address owner, address zeroXSwapper, uint16 lzChainId)
        private
        returns (TapiocaUtilitiesBatch utilitiesBatch, UtilitiesReport memory report)
    {
        utilitiesBatch = new TapiocaUtilitiesBatch(owner, zeroXSwapper, lzChainId, false);

        return (utilitiesBatch, utilitiesBatch.getUtilitiesReport());
    }

    function _deployYieldBox(
        address owner,
        address wrappedNativeToken,
        address pearlmit,
        address cluster,
        address swapper
    ) private returns (ExtExReport memory report) {
        TapiocaYieldboxBatch yieldboxBatch =
            new TapiocaYieldboxBatch(owner, wrappedNativeToken, pearlmit, cluster, swapper);
        return yieldboxBatch.getExtExReport();
    }

    function _deployPenrose(
        address yieldbox,
        address cluster,
        address tapToken,
        address usdoToken,
        address nativeWrappedToken,
        address pearlmit,
        address owner,
        address singularityMaster,
        address bigbangMaster,
        address prevPenrose
    ) private returns (PenroseReport memory report) {
        TapiocaPenroseBatch penroseBatch = new TapiocaPenroseBatch(
            IPenroseInput(
                yieldbox,
                cluster,
                tapToken,
                usdoToken,
                nativeWrappedToken,
                pearlmit,
                owner,
                singularityMaster,
                bigbangMaster,
                prevPenrose
            )
        );
        return penroseBatch.getPenroseReport();
    }

    function _deployBigBangModules(address endpoint, uint16 hostEid, address delegate)
        private
        returns (BBReport memory report)
    {
        TapiocaBBBatch1 bbBatchOne = new TapiocaBBBatch1();
        TapiocaBBBatch2 bbBatchTwo = new TapiocaBBBatch2(bbBatchOne.getBBReport());
        TapiocaBBBatch3 bbBatchThree = new TapiocaBBBatch3(bbBatchTwo.getBBReport());

        return bbBatchThree.getBBReport();
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

    /// @dev deploy singularity batches
    function _deploySingularity() private returns (SGLReport memory) {
        TapiocaSingularityBatch1 singularityBatch1 = new TapiocaSingularityBatch1();

        TapiocaSingularityBatch2 singularityBatch2 = new TapiocaSingularityBatch2(singularityBatch1.getSGLReport());

        TapiocaSingularityBatch3 singularityBatch3 = new TapiocaSingularityBatch3(singularityBatch2.getSGLReport());

        return singularityBatch3.getSGLReport();
    }

    function _deployTOFTModules(address endpoint, uint256 hostEid, address delegate, bool isMetaInstance)
        private
        returns (TOFTModulesReport memory report)
    {
        TapiocaTOFTModulesBatchOne toftModulesBatchOne = new TapiocaTOFTModulesBatchOne(endpoint, hostEid, delegate);
        if (isMetaInstance) {
            TapiocaTOFTMetaModulesBatchTwo toftModulesMetaBatchTwo =
                new TapiocaTOFTMetaModulesBatchTwo(toftModulesBatchOne.getTOFTModulesFirstReport());
            report = toftModulesMetaBatchTwo.getTOFTModulesSecondReport();
        } else {
            TapiocaTOFTModulesBatchTwo toftModulesBatchTwo =
                new TapiocaTOFTModulesBatchTwo(toftModulesBatchOne.getTOFTModulesFirstReport());

            report = toftModulesBatchTwo.getTOFTModulesSecondReport();
        }

        TapiocaTOFTModulesBatchThree toftModulesBatchThree = new TapiocaTOFTModulesBatchThree(report);

        report = toftModulesBatchThree.getTOFTModulesFinalReport();

        return report;
    }

    function _generateMarketReport(Reports memory reports) private pure returns (TapiocaReport memory) {
        TapiocaReport memory report;

        report.cluster = reports.utilitiesReport.cluster;
        report.pearlmit = reports.utilitiesReport.pearlmit;
        report.tapiocaMulticall = reports.utilitiesReport.tapiocaMulticall;
        report.toeHelper = reports.utilitiesReport.toeHelper;

        report.magnetarCollateralModule = reports.magnetarDepsReport.magnetarCollateralModule;
        report.magnetarMintModule = reports.magnetarDepsReport.magnetarMintModule;
        report.magnetarOptionModule = reports.magnetarDepsReport.magnetarOptionModule;
        report.simpleLeverageExecutor = reports.magnetarReport.simpleLeverageExecutor;
        report.magnetar = reports.magnetarReport.magnetar;
        report.magnetarHelper = reports.magnetarReport.magnetarHelper;
        report.liquidatorReceiver = reports.ExtExReport.liquidatorReceiver;
        report.extExec = reports.ExtExReport.extExec;
        report.usdoSenderModule = reports.usdoModulesReport.usdoSenderModule;
        report.usdoReceiverModule = reports.usdoModulesReport.usdoReceiverModule;
        report.marketReceiverModule = reports.usdoMarketModulesReport.marketReceiverModule;
        report.optionReceiverModule = reports.usdoMarketModulesReport.optionReceiverModule;
        report.usdo = reports.usdoReport.usdo;

        report.sglInit = reports.sglReport.sglInit;
        report.sglInterestHelper = reports.sglReport.sglInterestHelper;
        report.sglLiquidationModule = reports.sglReport.sglLiquidationModule;
        report.sglBorrowModule = reports.sglReport.sglBorrowModule;
        report.sglCollateralModule = reports.sglReport.sglCollateralModule;
        report.sglLeverageModule = reports.sglReport.sglLeverageModule;
        report.singularity = reports.sglReport.singularity;
        report.penrose = reports.penroseReport.penrose;
        report.tapStrat = reports.penroseReport.tapStrat;
        report.wrappedTokenStrat = reports.penroseReport.wrappedTokenStrat;
        report.usdoStrat = reports.penroseReport.usdoStrat;
        report.marketHelper = reports.penroseReport.marketHelper;

        report.bbLiquidation = reports.bbReport.bbLiquidation;
        report.bbBorrow = reports.bbReport.bbBorrow;
        report.bbCollateral = reports.bbReport.bbCollateral;
        report.bbLeverage = reports.bbReport.bbLeverage;
        report.bbDebtRateHelper = reports.bbReport.bbDebtRateHelper;
        report.bigbang = reports.bbReport.bigbang;

        report.tOFTSenderModule = reports.toftModulesReport.tOFTSenderModule;
        report.mTOFTReceiverModule = reports.toftModulesReport.mTOFTReceiverModule;
        report.tOFTReceiverModule = reports.toftModulesReport.tOFTReceiverModule;
        report.tOFTMarketReceiverModule = reports.toftModulesReport.tOFTMarketReceiverModule;
        report.tOFTOptionsReceiverModule = reports.toftModulesReport.tOFTOptionsReceiverModule;
        report.tOFTGenericReceiverModule = reports.toftModulesReport.tOFTGenericReceiverModule;
        report.toftHelper = reports.toftModulesReport.toftHelper;

        return report;
    }
}
