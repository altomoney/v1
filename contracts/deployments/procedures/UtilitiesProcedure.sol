// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {UtilitiesReport} from "../interfaces/IAltoReport.sol";

import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {TapiocaMulticallTestnet} from "tap-utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Pauser} from "tap-utils/Pauser/Pauser.sol";
import {ZeroXSwapper} from "tap-utils/Swapper/ZeroXSwapper.sol";
import {ZeroXSwapperMock} from "tapioca-mocks/ZeroXSwapperMock.sol";
import {ICluster} from "tap-utils/interfaces/common/ICluster.sol";
import {MultiTokenSender} from "tapioca-mocks/MultiTokenSender.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {AltoAdapter} from "@alto-monorepo/bundler/AltoAdapter.sol";
import {FixedRateIrm} from "@alto-monorepo/lending/FixedRateIrm.sol";
import {OracleMock} from "@alto-monorepo/lending/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto-monorepo/lending/interfaces/IOracle.sol";

abstract contract UtilitiesProcedure {
    function _deployUtilities(
        address owner,
        address zeroXProxy,
        uint32 lzChainId,
        bool isTestnet,
        address wrappedNativeToken
    ) internal returns (UtilitiesReport memory report) {
        report.bundler3 = address(new Bundler3());
        report.altoAdapter = address(new AltoAdapter(report.bundler3, wrappedNativeToken));
        if (isTestnet) {
            report.tapiocaMulticall = address(new TapiocaMulticallTestnet());
        } else {
            report.tapiocaMulticall = address(new TapiocaMulticall());
        }
        report.pauser = address(new Pauser(address(1), owner));
        if (isTestnet) {
            report.zeroXSwapper =
                zeroXProxy != address(0) ? zeroXProxy : address(new ZeroXSwapperMock(ICluster(address(1)), owner));
            report.multiTokenSender = address(new MultiTokenSender(owner));
        } else {
            report.zeroXSwapper = zeroXProxy != address(0)
                ? zeroXProxy
                : address(new ZeroXSwapper(zeroXProxy, ICluster(address(1)), owner));
        }
        if (isTestnet) {
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(owner, true);
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(address(this), false);
        } else {
            TapiocaMulticall(payable(report.tapiocaMulticall)).transferOwnership(owner);
        }

        report.borrowIrm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        report.mintIrm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));

        return report;
    }

    function _initCluster(
        address cluster,
        address zeroXSwapper,
        address penrose,
        address pauser,
        address tapiocaMulticall
    ) internal {
        Cluster(cluster).setRoleForContract(pauser, keccak256("PAUSER"), true);
        Cluster(cluster).updateContract(0, zeroXSwapper, true);
        Cluster(cluster).transferOwnership(tapiocaMulticall);
    }
}
