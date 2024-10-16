// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {PenroseReport, IPenroseInput} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaPenroseBatch
/// @notice Deploy Penrose
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaPenroseBatch is BarProcedure {
    PenroseReport internal _penroseReport;

    constructor(IPenroseInput memory input) {
        _penroseReport = _deployPenrose(input);
    }

    function getPenroseReport() external view returns (PenroseReport memory) {
        return _penroseReport;
    }
}
