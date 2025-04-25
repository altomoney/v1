// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {UsdoReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaUsdoBatch
/// @notice Deploy USDO contract
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaUsdoBatch is BarProcedure {
    UsdoReport internal _usdoReport;

    constructor(
        address endpoint,
        address delegate,
        address cluster
    ) {
        _usdoReport = _deployUsdo(
            endpoint,
            delegate,
            cluster
        );
    }

    function getUsdoReport() external view returns (UsdoReport memory) {
        return _usdoReport;
    }
}
