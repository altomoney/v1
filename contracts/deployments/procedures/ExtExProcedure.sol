// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ExtExReport} from "../interfaces/ITapiocaReport.sol";

import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {MarketLiquidatorReceiver} from "tapioca-bar/liquidators/MarketLiquidatorReceiver.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

abstract contract ExtExProcedure {
    function _deployExtEx(
        address owner,
        address wrappedNativeToken,
        address cluster,
        address swapper
    ) internal returns (ExtExReport memory report) {
        report.extExec = address(new TapiocaOmnichainExtExec());

        report.liquidatorReceiver =
            address(new MarketLiquidatorReceiver(wrappedNativeToken, ICluster(cluster), swapper, owner));
        return report;
    }
}
