// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {BBReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaPenroseBatch2
/// @notice Deploy Penrose
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaBBBatch2 is BarProcedure {
    BBReport internal _bbReport;

    constructor(BBReport memory input) {
        _bbReport = _deployBBModulesTwo(input);
    }

    function getBBReport() external view returns (BBReport memory) {
        return _bbReport;
    }
}
