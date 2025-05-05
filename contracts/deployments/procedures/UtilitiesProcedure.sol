// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {UtilitiesReport} from "../interfaces/ITapiocaReport.sol";

import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {TapiocaMulticallTestnet} from "tap-utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Pauser} from "tap-utils/Pauser/Pauser.sol";
import {ZeroXSwapper} from "tap-utils/Swapper/ZeroXSwapper.sol";
import {ZeroXSwapperMock} from "tapioca-mocks/ZeroXSwapperMock.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {MultiTokenSender} from "tapioca-mocks/MultiTokenSender.sol";

abstract contract UtilitiesProcedure {
    function _deployUtilities(address owner, address zeroXProxy, uint32 lzChainId, bool isTestnet)
        internal
        returns (UtilitiesReport memory report)
    {
        if (isTestnet) {
            report.tapiocaMulticall = address(new TapiocaMulticallTestnet());
        } else {
            report.tapiocaMulticall = address(new TapiocaMulticall());
        }
        report.cluster = address(new Cluster(lzChainId, address(this)));
        report.pauser = address(new Pauser(report.cluster, owner));
        if (isTestnet) {
            report.zeroXSwapper = zeroXProxy != address(0) ? zeroXProxy : address(new ZeroXSwapperMock(ICluster(report.cluster), owner));
            report.multiTokenSender = address(new MultiTokenSender(owner));
        } else {
            report.zeroXSwapper = zeroXProxy != address(0) ? zeroXProxy : address(new ZeroXSwapper(zeroXProxy, ICluster(report.cluster), owner));
        }
        if (isTestnet) {
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(owner, true);
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(address(this), false);
        } else {
            TapiocaMulticall(payable(report.tapiocaMulticall)).transferOwnership(owner);
        }
        return report;
    }

    function _initCluster(
        address cluster,
        address zeroXSwapper,
        address magnetar,
        address penrose,
        address pauser,
        address tapiocaMulticall
    ) internal {
        Cluster(cluster).setRoleForContract(magnetar, keccak256("TOE"), true);
        Cluster(cluster).setRoleForContract(pauser, keccak256("PAUSER"), true);
        Cluster(cluster).updateContract(0, magnetar, true);
        Cluster(cluster).updateContract(0, zeroXSwapper, true);
        Cluster(cluster).updateContract(0, penrose, true);
        Cluster(cluster).transferOwnership(tapiocaMulticall);
    }
}
