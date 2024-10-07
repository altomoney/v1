// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {BBReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaBBBatch1
/// @notice Deploy big bang modules
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaBBBatch1 is BarProcedure {
    BBReport internal _bbReport;

    constructor() {
        _bbReport = _deployBBModulesOne();
    }

    function getBBReport() external view returns (BBReport memory) {
        return _bbReport;
    }
}
