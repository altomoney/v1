// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TapiocaMagnetarBatchOne} from "contracts/deployments/releases/tapioca-v1/batches/TapiocaMagnetarBatchOne.sol";
import {TapiocaMagnetarBatchTwo} from "contracts/deployments/releases/tapioca-v1/batches/TapiocaMagnetarBatchTwo.sol";
import {Script} from "forge-std/Script.sol";

contract DeployMagnetarTestnet is Script {
    function run() external {
        // Update these values with the values from previous deployment report
        address cluster = 0x19B7a58909B6B4d65a4fe4E754ac800D536ab15E;
        address owner = 0x4778c2AA94a8D05D63e4C07eb68021528985304C;
        address nativeTokenWrapper = 0xEDD8350720a1F54A271ee106FfCa30F89e213F4b;

        vm.startBroadcast();

        TapiocaMagnetarBatchOne magnetarBatch = new TapiocaMagnetarBatchOne();
        TapiocaMagnetarBatchTwo magnetarBatchTwo = new TapiocaMagnetarBatchTwo(
            owner,
            cluster,
            address(0x0000000000000000000000000000000000000000),
            nativeTokenWrapper,
            magnetarBatch.getMagnetarDepsReport()
        );
    }
}
