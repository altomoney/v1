// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SGLProcedure} from "../../../procedures/SGLProcedure.sol";
import {SGLReport} from "../../../interfaces/ITapiocaReport.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";

/// @title TapiocaSingularityBatch4
/// @notice Deploy Singularity contracts and modules
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaSingularityBatch4 is SGLProcedure {
    SGLReport internal _sglReport;

    constructor(SGLReport memory inputSglReport) {
        _sglReport = _deploySglModulesFour(inputSglReport);
    }

    function _deploySglModulesFour(SGLReport memory report) internal returns (SGLReport memory) {
        report.sglInit = address(new SGLInit());
        return report;
    }

    function getSGLReport() external view returns (SGLReport memory) {
        return _sglReport;
    }
}
