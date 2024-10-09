// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {TapiocaReport, TapiocaInput} from "deployments/interfaces/ITapiocaReport.sol";

import {Script} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract DeployTapiocaHostTestnet is Script {
    using stdJson for string;

    function run() public {
        TapiocaInput memory input;
        TapiocaReport memory report;
        TapiocaReport memory prevReport;

        // TODO: all input params are demo values
        input.owner = msg.sender;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(0);
        input.isTestnet = true;

        vm.startBroadcast();
        report = TapiocaRelease.deployTapiocaV1(input, prevReport);
        vm.stopBroadcast();
    }
}
