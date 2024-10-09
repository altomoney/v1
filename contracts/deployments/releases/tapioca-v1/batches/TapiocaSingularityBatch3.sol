// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {SGLProcedure} from "../../../procedures/SGLProcedure.sol";
import {SGLReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaSingularityBatch3
/// @notice Deploy Singularity contracts and modules
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaSingularityBatch3 is SGLProcedure {
    SGLReport internal _sglReport;

    constructor(SGLReport memory inputSglReport) {
        _sglReport = _deploySglModulesThree(inputSglReport);
    }

    function getSGLReport() external view returns (SGLReport memory) {
        return _sglReport;
    }
}
