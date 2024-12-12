// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {MagnetarProcedure} from "../../../procedures/MagnetarProcedure.sol";
import {MagnetarReport, MagnetarDepsReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaMagnetarBatchTwo
/// @notice Deploy Magnetar module contracts
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaMagnetarBatchTwo is MagnetarProcedure {
    MagnetarReport internal _magnetarReport;

    constructor(
        address owner,
        address cluster,
        address toeHelper,
        address zeroXSwap,
        address nativeTokenWrapper,
        MagnetarDepsReport memory deps
    ) {
        _magnetarReport = _deployMagnetar(owner, cluster, toeHelper, zeroXSwap, nativeTokenWrapper, deps);
    }

    function getMagnetarReport() external view returns (MagnetarReport memory) {
        return _magnetarReport;
    }
}
