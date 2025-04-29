// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TapiocaMagnetarBatchOne} from "./batches/TapiocaMagnetarBatchOne.sol";
import {TapiocaMagnetarBatchTwo} from "./batches/TapiocaMagnetarBatchTwo.sol";
import {TapiocaUtilitiesBatch} from "./batches/TapiocaUtilitiesBatch.sol";
import {TapiocaExtExBatch} from "./batches/TapiocaExtExBatch.sol";
import {TapiocaUsdoBatch} from "./batches/TapiocaUsdoBatch.sol";
import {TapiocaSingularityBatch1} from "./batches/TapiocaSingularityBatch1.sol";
import {TapiocaSingularityBatch2} from "./batches/TapiocaSingularityBatch2.sol";
import {TapiocaSingularityBatch3} from "./batches/TapiocaSingularityBatch3.sol";
import {TapiocaSingularityBatch4} from "./batches/TapiocaSingularityBatch4.sol";
import {TapiocaPenroseBatch} from "./batches/TapiocaPenroseBatch.sol";
import {TapiocaBBBatch1} from "./batches/TapiocaBBBatch1.sol";
import {TapiocaBBBatch2} from "./batches/TapiocaBBBatch2.sol";
import {TapiocaBBBatch3} from "./batches/TapiocaBBBatch3.sol";
import {SingularityLauncher} from "./actions/SingularityLauncher.sol";
import {BigBangLauncher} from "./actions/BigBangLauncher.sol";

// Temp imports due codesize limit in batches
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import "../../interfaces/ITapiocaReport.sol";
import "forge-std/console.sol";

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
        (utilitiesBatch, reports.utilitiesReport) =
            _deployUtilities(input.owner, input.zeroXProxy, input.lzChainId, input.isTestnet);

        reports.ExtExReport = _deployExtEx(
            input.owner, input.wrappedNativeToken, reports.utilitiesReport.cluster, reports.utilitiesReport.zeroXSwapper
        );

        reports.magnetarDepsReport = _deployMagnetarDeps();

        reports.magnetarReport = _deployMagnetar(
            input.owner,
            reports.utilitiesReport.cluster,
            reports.utilitiesReport.zeroXSwapper,
            input.wrappedNativeToken,
            reports.magnetarDepsReport
        );

        reports.usdoReport = _deployUSDO(
            input.lzEndpoint,
            input.owner, // delegate
            reports.utilitiesReport.cluster
        );

        reports.sglReport = _deploySingularity();

        reports.bbReport =
            _deployBigBangModules(input.lzEndpoint, input.lzChainId, reports.utilitiesReport.tapiocaMulticall);
        reports.penroseReport = _deployPenrose(
            reports.utilitiesReport.cluster,
            input.tapToken,
            reports.usdoReport.usdo,
            input.wrappedNativeToken,
            reports.utilitiesReport.tapiocaMulticall,
            reports.sglReport.singularity,
            reports.bbReport.bigbang,
            reports.magnetarReport.magnetar,
            prevReport.penrose
        );
        reports.launcherReport = _deployMarketLaunchers(
            reports.sglReport,
            reports.bbReport,
            reports.penroseReport.penrose,
            reports.magnetarReport.simpleLeverageExecutor,
            input.bbMarketBorrowCap
        );

        utilitiesBatch.initializeCluster(
            reports.utilitiesReport.cluster,
            reports.utilitiesReport.zeroXSwapper,
            reports.magnetarReport.magnetar,
            reports.penroseReport.penrose,
            reports.utilitiesReport.pauser,
            reports.utilitiesReport.tapiocaMulticall
        );

        return _generateMarketReport(reports);
    }

    ///
    /// Internal functions for deployment of batch contracts and retrieval of deployment report
    ///

    function _deployMagnetarDeps() private returns (MagnetarDepsReport memory report) {
        TapiocaMagnetarBatchOne magnetarDepsBatch = new TapiocaMagnetarBatchOne();
        return magnetarDepsBatch.getMagnetarDepsReport();
    }

    function _deployMagnetar(
        address owner,
        address cluster,
        address zeroXSwapper,
        address wrappedNativeToken,
        MagnetarDepsReport memory deps
    ) private returns (MagnetarReport memory report) {
        TapiocaMagnetarBatchTwo magnetarBatchTwo =
            new TapiocaMagnetarBatchTwo(owner, cluster, zeroXSwapper, wrappedNativeToken, deps);
        return magnetarBatchTwo.getMagnetarReport();
    }

    function _deployUtilities(address owner, address zeroXSwapper, uint16 lzChainId, bool isTestnet)
        private
        returns (TapiocaUtilitiesBatch utilitiesBatch, UtilitiesReport memory report)
    {
        utilitiesBatch = new TapiocaUtilitiesBatch(owner, zeroXSwapper, lzChainId, isTestnet);

        return (utilitiesBatch, utilitiesBatch.getUtilitiesReport());
    }

    function _deployExtEx(address owner, address wrappedNativeToken, address cluster, address swapper)
        private
        returns (ExtExReport memory report)
    {
        TapiocaExtExBatch extExBatch = new TapiocaExtExBatch(owner, wrappedNativeToken, cluster, swapper);
        return extExBatch.getExtExReport();
    }

    function _deployPenrose(
        address cluster,
        address tapToken,
        address usdoToken,
        address nativeWrappedToken,
        address owner,
        address singularityMaster,
        address bigbangMaster,
        address magnetar,
        address prevPenrose
    ) private returns (PenroseReport memory report) {
        TapiocaPenroseBatch penroseBatch = new TapiocaPenroseBatch(
            IPenroseInput(
                cluster, tapToken, usdoToken, nativeWrappedToken, owner, singularityMaster, bigbangMaster, magnetar, prevPenrose
            )
        );
        return penroseBatch.getPenroseReport();
    }

    function _deployBigBangModules(address endpoint, uint16 hostEid, address delegate)
        private
        returns (BBReport memory report)
    {
        BBReport memory batchReportOne;

        // TapiocaBBBatch1 bbBatchOne = new TapiocaBBBatch1(); Due code size limit skipped, using direct deployment
        batchReportOne.bbLiquidation = address(new BBLiquidation());
        batchReportOne.bbBorrow = address(new BBBorrow());
        batchReportOne.bbLeverage = address(new BBLeverage());

        TapiocaBBBatch2 bbBatchTwo = new TapiocaBBBatch2(batchReportOne);
        TapiocaBBBatch3 bbBatchThree = new TapiocaBBBatch3(bbBatchTwo.getBBReport());

        report = bbBatchThree.getBBReport();
        report.bbDebtRateHelper = address(new BBDebtRateHelper());

        return report;
    }

    function _deployMarketLaunchers(
        SGLReport memory sglReport,
        BBReport memory bbReport,
        address penrose,
        address leverageExecutor,
        uint256 bbMarketBorrowCap
    ) private returns (LauncherReport memory report) {
        BigBangLauncher bigBangLauncher = new BigBangLauncher(
            bbReport.bbLiquidation,
            bbReport.bbBorrow,
            bbReport.bbCollateral,
            bbReport.bbLeverage,
            penrose,
            leverageExecutor,
            bbReport.bigbang,
            bbReport.bbDebtRateHelper,
            bbMarketBorrowCap
        );
        SingularityLauncher singularityLauncher = new SingularityLauncher(
            sglReport.sglLiquidationModule,
            sglReport.sglBorrowModule,
            sglReport.sglCollateralModule,
            sglReport.sglLeverageModule,
            sglReport.sglInit,
            penrose,
            leverageExecutor,
            sglReport.sglInterestHelper,
            sglReport.singularity
        );
        report.singularityLauncher = address(singularityLauncher);
        report.bigBangLauncher = address(bigBangLauncher);

        return report;
    }

    function _deployUSDO(address endpoint, address delegate, address cluster)
        private
        returns (
            UsdoReport memory usdoReport
        )
    {
        TapiocaUsdoBatch usdoBatch = new TapiocaUsdoBatch(
            endpoint,
            delegate,
            cluster
        );
        usdoReport = usdoBatch.getUsdoReport();
        return (usdoReport);
    }

    /// @dev deploy singularity batches
    function _deploySingularity() private returns (SGLReport memory) {
        TapiocaSingularityBatch1 singularityBatch1 = new TapiocaSingularityBatch1();

        TapiocaSingularityBatch2 singularityBatch2 = new TapiocaSingularityBatch2(singularityBatch1.getSGLReport());

        TapiocaSingularityBatch3 singularityBatch3 = new TapiocaSingularityBatch3(singularityBatch2.getSGLReport());

        TapiocaSingularityBatch4 singularityBatch4 = new TapiocaSingularityBatch4(singularityBatch3.getSGLReport());

        SGLReport memory report = singularityBatch4.getSGLReport();
        report.sglBorrowModule = address(new SGLBorrow());
        report.sglCollateralModule = address(new SGLCollateral());

        return report;
    }

    function _generateMarketReport(Reports memory reports) private pure returns (TapiocaReport memory) {
        TapiocaReport memory report;

        report.cluster = reports.utilitiesReport.cluster;
        report.altoAdaptiveCurveIrm = reports.utilitiesReport.altoAdaptiveCurveIrm;
        report.tapiocaMulticall = reports.utilitiesReport.tapiocaMulticall;
        report.multiTokenSender = reports.utilitiesReport.multiTokenSender;
        report.zeroXSwapper = reports.utilitiesReport.zeroXSwapper;

        report.magnetarCollateralModule = reports.magnetarDepsReport.magnetarCollateralModule;
        report.magnetarMintModule = reports.magnetarDepsReport.magnetarMintModule;
        report.magnetarOptionModule = reports.magnetarDepsReport.magnetarOptionModule;
        report.magnetarLeverageModule = reports.magnetarDepsReport.magnetarLeverageModule;
        report.simpleLeverageExecutor = reports.magnetarReport.simpleLeverageExecutor;
        report.magnetar = reports.magnetarReport.magnetar;
        report.magnetarHelper = reports.magnetarDepsReport.magnetarHelper;
        report.liquidatorReceiver = reports.ExtExReport.liquidatorReceiver;
        report.extExec = reports.ExtExReport.extExec;
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

        report.singularityLauncher = reports.launcherReport.singularityLauncher;
        report.bigBangLauncher = reports.launcherReport.bigBangLauncher;

        return report;
    }
}
