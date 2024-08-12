// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {UtilitiesReport} from "../interfaces/ITapiocaReport.sol";
import {Pearlmit} from "tap-utils/pearlmit/Pearlmit.sol";
import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {IWrappedNative} from "tap-yieldbox/interfaces/IWrappedNative.sol";
import {TapiocaOmnichainEngineHelper} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";
import {Pauser} from "tap-utils/Pauser/Pauser.sol";
import {ZeroXSwapper} from "tap-utils/Swapper/ZeroXSwapper.sol";
import {ZeroXSwapperMock} from "tapioca-mocks/ZeroXSwapperMock.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

abstract contract UtilitiesProcedure {
    function _deployUtilities(
        address owner,
        address zeroXProxy,
        address wrappedNativeToken,
        uint32 lzChainId,
        bool isTestnet
    ) internal returns (UtilitiesReport memory report) {
        report.tapiocaMulticall = address(new TapiocaMulticall());
        report.pearlmit = address(new Pearlmit("PEARLMIT", "1", report.tapiocaMulticall, 0));
        report.cluster = address(new Cluster(lzChainId, report.tapiocaMulticall));
        report.toeHelper = address(new TapiocaOmnichainEngineHelper());
        report.pauser = address(new Pauser(report.cluster, owner));
        if (isTestnet) {
            report.zeroXSwapper = address(new ZeroXSwapperMock(ICluster(report.cluster), owner));
        } else {
            report.zeroXSwapper = address(new ZeroXSwapper(zeroXProxy, ICluster(report.cluster), owner));
        }

        return report;
    }
}
