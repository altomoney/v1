// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {AltoMulticall} from "@alto/deployments/contracts/multicall/AltoMulticall.sol";
import {Usdo} from "@alto/tokens/Usdo.sol";

// catapulta script script/single/UsdoSetMinterBurner.s.sol:UsdoSetMinterBurner --rpc-url <network-rpc-url> -vvvv --sender <sender_address>
contract UsdoSetMinterBurner is Script {
    function run() public {
        address multicall = vm.envAddress("MULTICALL_ADDRESS");
        address usdo = vm.envAddress("USDO_ADDRESS");
        address target = vm.envAddress("TARGET_ADDRESS");
        bool status = vm.envBool("STATUS");

        vm.startBroadcast();
        AltoMulticall.Call[] memory calls = new AltoMulticall.Call[](2);
        calls[0] = AltoMulticall.Call({
            target: usdo,
            allowFailure: false,
            callData: abi.encodeWithSelector(Usdo.setMinterStatus.selector, target, status)
        });
        calls[1] = AltoMulticall.Call({
            target: usdo,
            allowFailure: false,
            callData: abi.encodeWithSelector(Usdo.setBurnerStatus.selector, target, status)
        });
        AltoMulticall(payable(multicall)).multicall(calls);

        vm.stopBroadcast();
    }
}
