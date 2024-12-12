// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {UsdoMarketModulesReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaUsdoBatchOne
/// @notice Deploy USDO contracts and modules
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaUsdoBatchTwo is BarProcedure {
    UsdoMarketModulesReport internal _usdoMarketModulesReport;

    constructor(
        address endpoint,
        address delegate,
        address cluster,
        address extExec
    ) {
        _usdoMarketModulesReport = _deployUsdoMarketModules(endpoint, delegate, cluster, extExec);
    }

    function getUsdoMarketModulesReport() external view returns (UsdoMarketModulesReport memory) {
        return _usdoMarketModulesReport;
    }
}
