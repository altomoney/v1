// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {MagnetarProcedure} from "../../../procedures/MagnetarProcedure.sol";
import {MagnetarDepsReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaMagnetarBatchOne
/// @notice Deploy Magnetar contracts
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaMagnetarBatchOne is MagnetarProcedure {
    MagnetarDepsReport internal _magnetarDepsReport;

    constructor() {
        _magnetarDepsReport = _deployMagnetarDeps();
    }

    function getMagnetarDepsReport() external view returns (MagnetarDepsReport memory) {
        return _magnetarDepsReport;
    }
}
