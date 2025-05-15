// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {TapiocaMulticall} from "@alto-monorepo/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Usdo} from "../../contracts/bar/usdo/Usdo.sol";

// catapulta script script/single/UsdoSetMinterBurner.s.sol:UsdoSetMinterBurner --rpc-url <network-rpc-url> -vvvv --sender <sender_address>
contract UsdoSetMinterBurner is Script {
    function run() public {
        address multicall = vm.envAddress("MULTICALL_ADDRESS");
        address usdo = vm.envAddress("USDO_ADDRESS");
        address target = vm.envAddress("TARGET_ADDRESS");
        bool status = vm.envBool("STATUS");

        vm.startBroadcast();
        TapiocaMulticall.Call[] memory calls = new TapiocaMulticall.Call[](2);
        calls[0] = TapiocaMulticall.Call({
            target: usdo,
            allowFailure: false,
            callData: abi.encodeWithSelector(Usdo.setMinterStatus.selector, target, status)
        });
        calls[1] = TapiocaMulticall.Call({
            target: usdo,
            allowFailure: false,
            callData: abi.encodeWithSelector(Usdo.setBurnerStatus.selector, target, status)
        });
        TapiocaMulticall(payable(multicall)).multicall(calls);

        vm.stopBroadcast();
    }
}
