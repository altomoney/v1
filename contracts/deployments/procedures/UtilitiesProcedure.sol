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
import "forge-std/console.sol";

abstract contract UtilitiesProcedure {
    function _deployUtilities(address owner, address zeroXProxy, uint32 lzChainId, bool isTestnet)
        internal
        returns (UtilitiesReport memory report)
    {
        report.tapiocaMulticall = address(new TapiocaMulticall());
        report.pearlmit = address(new Pearlmit("PEARLMIT", "1", report.tapiocaMulticall, 0));
        report.cluster = address(new Cluster(lzChainId, address(this)));
        report.toeHelper = address(new TapiocaOmnichainEngineHelper());
        report.pauser = address(new Pauser(report.cluster, owner));
        if (isTestnet) {
            report.zeroXSwapper = address(new ZeroXSwapperMock(ICluster(report.cluster), owner));
        } else {
            report.zeroXSwapper = address(new ZeroXSwapper(zeroXProxy, ICluster(report.cluster), owner));
        }
        TapiocaMulticall(report.tapiocaMulticall).transferOwnership(owner);
        return report;
    }

    function _initCluster(
        address cluster,
        address zeroXSwapper,
        address yieldbox,
        address magnetar,
        address penrose,
        address pauser,
        address tapiocaMulticall
    ) internal {
        Cluster(cluster).setRoleForContract(magnetar, keccak256("TOE"), true);
        Cluster(cluster).setRoleForContract(pauser, keccak256("PAUSER"), true);
        Cluster(cluster).updateContract(0, yieldbox, true);
        Cluster(cluster).updateContract(0, magnetar, true);
        Cluster(cluster).updateContract(0, zeroXSwapper, true);
        Cluster(cluster).updateContract(0, penrose, true);
        Cluster(cluster).transferOwnership(tapiocaMulticall);
    }
}
