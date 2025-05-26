// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {UtilitiesReport} from "../interfaces/IAltoReport.sol";

import {TapiocaMulticall} from "@alto/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {TapiocaMulticallTestnet} from "@alto/utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {Cluster} from "@alto/utils/Cluster/Cluster.sol";
import {ICluster} from "@alto/utils/interfaces/common/ICluster.sol";
import {MultiTokenSender} from "@alto/deployments/testnet/MultiTokenSender.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";

abstract contract UtilitiesProcedure {
    int256 internal constant YEAR = int256(365 days);

    function _deployUtilities(address owner, uint32 lzChainId, bool isTestnet, address wrappedNativeToken)
        internal
        returns (UtilitiesReport memory report)
    {
        report.bundler3 = address(new Bundler3());
        report.altoAdapter = address(new AltoAdapter(report.bundler3, wrappedNativeToken));
        if (isTestnet) {
            report.tapiocaMulticall = address(new TapiocaMulticallTestnet());
        } else {
            report.tapiocaMulticall = address(new TapiocaMulticall());
        }
        if (isTestnet) {
            report.leverageSwapper = address(new SwapperSimpleMock(address(this)));
            report.multiTokenSender = address(new MultiTokenSender(owner));
        } else {
            // TODO: Implement mainnet swpper deployment once we have it
            revert("NOT_IMPLEMENTED");
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
        report.altoLeverage = address(new AltoLeverage(report.leverageSwapper, owner));
        if (isTestnet) {
            SwapperSimpleMock(payable(report.leverageSwapper)).setWhitelisted(address(report.altoLeverage), true);
            SwapperSimpleMock(payable(report.leverageSwapper)).transferOwnership(owner);
        }
        return report;
    }
}
