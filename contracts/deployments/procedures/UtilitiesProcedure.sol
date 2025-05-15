// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {UtilitiesReport} from "../interfaces/IAltoReport.sol";

import {TapiocaMulticall} from "@alto-monorepo/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {TapiocaMulticallTestnet} from "@alto-monorepo/utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {Cluster} from "@alto-monorepo/utils/Cluster/Cluster.sol";
import {Pauser} from "@alto-monorepo/utils/Pauser/Pauser.sol";
import {ZeroXSwapper} from "@alto-monorepo/utils/Swapper/ZeroXSwapper.sol";
import {ZeroXSwapperMock} from "@alto-monorepo/mocks/ZeroXSwapperMock.sol";
import {ICluster} from "@alto-monorepo/utils/interfaces/common/ICluster.sol";
import {MultiTokenSender} from "@alto-monorepo/mocks/MultiTokenSender.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {AltoAdapter} from "@alto-monorepo/bundler/AltoAdapter.sol";
import {AdaptiveCurveIrm} from "@alto-monorepo/lending/AdaptiveCurveIrm.sol";
import {OracleMock} from "@alto-monorepo/lending/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto-monorepo/lending/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto-monorepo/bar/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto-monorepo/mocks/SwapperSimpleMock.sol";

abstract contract UtilitiesProcedure {
    int256 internal constant YEAR = int256(365 days);

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
            report.zeroXSwapper = zeroXProxy != address(0) ? zeroXProxy : address(new SwapperSimpleMock(owner));
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
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory config = AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 4 ether,
            adjustmentSpeed: 50 ether / YEAR,
            targetUtilization: 0.8 ether,
            initialRateAtTarget: 0.04 ether / YEAR,
            minRateAtTarget: 0.001e18 / YEAR,
            maxRateAtTarget: 2 ether / YEAR
        });

        report.borrowIrm = address(new AdaptiveCurveIrm(config, owner));
        report.mintIrm = address(new AdaptiveCurveIrm(config, owner));
        report.altoLeverage = address(new AltoLeverage(report.zeroXSwapper, owner));

        return report;
    }
}
