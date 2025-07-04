// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {UsdoProcedure} from "../../../procedures/UsdoProcedure.sol";
import {UsdoReport} from "../../../interfaces/IAltoReport.sol";
import {AltoProcedure, AltoTokenReport} from "../../../procedures/AltoProcedure.sol";

/// @title AltoTokenRewardsBatch
/// @notice Deploy ALTO token and rewards distributor contract
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract AltoTokenRewardsBatch is AltoProcedure {
    AltoTokenReport internal _altoTokenReport;

    constructor(address endpoint, address delegate) {
        _altoTokenReport = _deployAltoToken(endpoint, delegate);
    }

    function getAltoTokenReport() external view returns (AltoTokenReport memory) {
        return _altoTokenReport;
    }
}
