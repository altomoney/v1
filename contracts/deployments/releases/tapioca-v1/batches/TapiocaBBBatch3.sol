// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {BBReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaBBBatch3
/// @notice Deploy big bang
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaBBBatch3 is BarProcedure {
    BBReport internal _bbReport;

    constructor(BBReport memory input) {
        _bbReport = _deployBBModulesThree(input);
    }

    function getBBReport() external view returns (BBReport memory) {
        return _bbReport;
    }
}
