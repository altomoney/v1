// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {SGLReport} from "../interfaces/ITapiocaReport.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {SGLInterestHelper} from "tapioca-bar/markets/singularity/SGLInterestHelper.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";

abstract contract SGLProcedure {
    function _deploySglModulesOne() internal returns (SGLReport memory report) {
        report.sglBorrowModule = address(new SGLBorrow());
        report.sglInterestHelper = address(new SGLInterestHelper());
        report.sglLeverageModule = address(new SGLLeverage());
        return report;
    }

    function _deploySglModulesTwo(SGLReport memory report) internal returns (SGLReport memory) {
        report.sglLiquidationModule = address(new SGLLiquidation());
        report.sglCollateralModule = address(new SGLCollateral());
        return report;
    }

    function _deploySglModulesThree(SGLReport memory report) internal returns (SGLReport memory) {
        report.sglInit = address(new SGLInit());
        report.singularity = address(new Singularity());
        return report;
    }
}
