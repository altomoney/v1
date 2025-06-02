// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {UsdoProcedure} from "../../../procedures/UsdoProcedure.sol";
import {UsdoReport} from "../../../interfaces/IAltoReport.sol";

/// @title AltoUsdoBatch
/// @notice Deploy USDO contract
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract AltoUsdoBatch is UsdoProcedure {
    UsdoReport internal _usdoReport;

    constructor(address endpoint, address delegate) {
        _usdoReport = _deployUsdo(endpoint, delegate);
    }

    function getUsdoReport() external view returns (UsdoReport memory) {
        return _usdoReport;
    }
}
