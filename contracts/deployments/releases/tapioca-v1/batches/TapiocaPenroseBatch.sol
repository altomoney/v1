// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {PenroseReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaPenroseBatch
/// @notice Deploy Penrose
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaPenroseBatch is BarProcedure {
    PenroseReport internal _penroseReport;

    constructor(
        address yieldbox,
        address cluster,
        address tapToken,
        address usdoToken,
        address nativeWrappedToken,
        address pearlmit,
        address owner
    ) {
        _penroseReport = _deployPenrose(yieldbox, cluster, tapToken, usdoToken, nativeWrappedToken, pearlmit, owner);
    }

    function getPenroseReport() external view returns (PenroseReport memory) {
        return _penroseReport;
    }
}
