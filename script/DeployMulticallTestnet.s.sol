// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {getMulticallOwnerAddresses} from "@alto/deployments/testnet/Constants.sol";

contract DeployMulticallTestnet is Script {
    function run() public {
        vm.startBroadcast();
        address altoMulticall = address(new AltoMulticallTestnet());
        address[] memory ownerAddresses = getMulticallOwnerAddresses();
        for (uint256 i = 0; i < ownerAddresses.length; i++) {
            AltoMulticallTestnet(payable(altoMulticall)).setOwner(ownerAddresses[i], true);
        }
        console.log("Alto Multicall deployed at", altoMulticall);
        vm.stopBroadcast();
    }
}
