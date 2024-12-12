// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {UsdoModulesReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaUsdoBatchOne
/// @notice Deploy USDO contracts and modules
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaUsdoBatchOne is BarProcedure {
    UsdoModulesReport internal _usdoModulesReport;

    constructor(
        address endpoint,
        address delegate,
        address cluster,
        address extExec
    ) {
        _usdoModulesReport = _deployUsdoSenderAndReceiver(endpoint, delegate, cluster, extExec);
    }

    function getUsdoModulesReport() external view returns (UsdoModulesReport memory) {
        return _usdoModulesReport;
    }
}
