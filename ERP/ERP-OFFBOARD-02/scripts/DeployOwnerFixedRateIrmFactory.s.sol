// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";

/// @notice Deploys the OwnerFixedRateIrmFactory with the production Timelock as its initial owner.
contract DeployOwnerFixedRateIrmFactoryScript is Script {
    string public constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    function run() external returns (address factoryAddress) {
        require(block.chainid == 1, "Factory deploy: Ethereum mainnet only");

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        address timelock = vm.parseJsonAddress(addresses, ".contracts.timelock");
        require(timelock != address(0) && timelock.code.length != 0, "Factory deploy: invalid Timelock");

        vm.startBroadcast();
        OwnerFixedRateIrmFactory factory = new OwnerFixedRateIrmFactory(timelock);
        vm.stopBroadcast();

        require(factory.owner() == timelock, "Factory deploy: wrong owner");
        require(factory.pendingOwner() == address(0), "Factory deploy: unexpected pending owner");
        require(factory.nonce() == 0, "Factory deploy: non-zero initial nonce");
        factoryAddress = address(factory);

        console2.log("OwnerFixedRateIrmFactory:", factoryAddress);
        console2.log("Owner (Timelock):", timelock);
    }
}
