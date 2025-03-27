// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";

contract Whitelist is Script {
    function run() public {
        vm.startBroadcast();
        address multicall = vm.envAddress("MULTICALL_ADDRESS");
        address cluster = vm.envAddress("CLUSTER_ADDRESS");
        address target = vm.envAddress("TARGET_ADDRESS");
        bool status = vm.envBool("STATUS");

        TapiocaMulticall.Call[] memory calls = new TapiocaMulticall.Call[](1);

        calls[0] = TapiocaMulticall.Call({
            target: cluster,
            allowFailure: false,
            callData: abi.encodeWithSelector(Cluster.updateContract.selector, 0, target, status)
        });

        TapiocaMulticall(payable(multicall)).multicall(calls);

        vm.stopBroadcast();
    }
}
