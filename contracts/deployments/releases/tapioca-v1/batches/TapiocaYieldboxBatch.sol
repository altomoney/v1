// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {YieldboxProcedure} from "../../../procedures/YieldboxProcedure.sol";
import {ExtExReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaYieldboxBatch
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaYieldboxBatch is YieldboxProcedure {
    ExtExReport internal _ExtExReport;

    constructor(address owner, address wrappedNativeToken, address pearlmit, address cluster, address swapper) {
        _ExtExReport = _deployYieldbox(owner, wrappedNativeToken, pearlmit, cluster, swapper);
    }

    function getExtExReport() public view returns (ExtExReport memory) {
        return _ExtExReport;
    }
}
