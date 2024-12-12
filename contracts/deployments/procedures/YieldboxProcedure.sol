// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ExtExReport} from "../interfaces/ITapiocaReport.sol";

import {YieldBox} from "tap-yieldbox/YieldBox.sol";
import {YieldBoxURIBuilder} from "tap-yieldbox/YieldBoxURIBuilder.sol";
import {IWrappedNative} from "tap-yieldbox/interfaces/IWrappedNative.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {MarketLiquidatorReceiver} from "tapioca-bar/liquidators/MarketLiquidatorReceiver.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

abstract contract YieldboxProcedure {
    function _deployYieldbox(
        address owner,
        address wrappedNativeToken,
        address pearlmit,
        address cluster,
        address swapper
    ) internal returns (ExtExReport memory report) {
        report.yieldboxUri = address(new YieldBoxURIBuilder());
        report.yieldbox = address(
            new YieldBox(
                IWrappedNative(wrappedNativeToken), YieldBoxURIBuilder(report.yieldboxUri), Pearlmit(pearlmit), owner
            )
        );
        report.extExec = address(new TapiocaOmnichainExtExec());

        report.liquidatorReceiver =
            address(new MarketLiquidatorReceiver(wrappedNativeToken, ICluster(cluster), swapper, owner));
        return report;
    }
}
