// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {YieldboxProcedure} from "../../../procedures/YieldboxProcedure.sol";
import {YieldboxReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaYieldboxBatch
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaYieldboxBatch is YieldboxProcedure {
    YieldboxReport internal _yieldboxReport;

    constructor(address owner, address wrappedNativeToken, address pearlmit, address cluster, address swapper) {
        _yieldboxReport = _deployYieldbox(owner, wrappedNativeToken, pearlmit, cluster, swapper);
    }

    function getYieldboxReport() public view returns (YieldboxReport memory) {
        return _yieldboxReport;
    }
}
