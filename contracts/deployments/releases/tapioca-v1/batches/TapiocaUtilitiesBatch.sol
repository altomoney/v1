// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {UtilitiesProcedure} from "../../../procedures/UtilitiesProcedure.sol";
import {UtilitiesReport} from "../../../interfaces/ITapiocaReport.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TapiocaUtiltiiesBatch
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaUtilitiesBatch is UtilitiesProcedure, Ownable {
    UtilitiesReport internal _utilitiesReport;

    constructor(address owner, address zeroXSwapper, uint16 lzChainId, bool isTestnet) Ownable() {
        _utilitiesReport = _deployUtilities(owner, zeroXSwapper, lzChainId, isTestnet);
    }

    function initializeCluster(
        address cluster,
        address zeroXSwapper,
        address yieldbox,
        address magnetar,
        address penrose,
        address pauser,
        address tapiocaMulticall
    ) external onlyOwner {
        _initCluster(cluster, zeroXSwapper, yieldbox, magnetar, penrose, pauser, tapiocaMulticall);
    }

    function getUtilitiesReport() public view returns (UtilitiesReport memory) {
        return _utilitiesReport;
    }
}
