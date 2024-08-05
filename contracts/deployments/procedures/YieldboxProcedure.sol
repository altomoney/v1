// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {YieldboxReport} from "../interfaces/ITapiocaReport.sol";
import {Pearlmit} from "tap-utils/pearlmit/Pearlmit.sol";
import {YieldBox} from "tap-yieldbox/YieldBox.sol";
import {YieldBoxURIBuilder} from "tap-yieldbox/YieldBoxURIBuilder.sol";
import {IWrappedNative} from "tap-yieldbox/interfaces/IWrappedNative.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import "forge-std/console2.sol";

abstract contract YieldboxProcedure {
    function _deployYieldbox(address owner, address wrappedNativeToken, address pearlmit)
        internal
        returns (YieldboxReport memory report)
    {
        report.yieldboxUri = address(new YieldBoxURIBuilder());
        report.yieldbox = address(
            new YieldBox(
                IWrappedNative(wrappedNativeToken), YieldBoxURIBuilder(report.yieldboxUri), Pearlmit(pearlmit), owner
            )
        );
        report.delegate = address(new TapiocaOmnichainExtExec());
        return report;
    }
}
