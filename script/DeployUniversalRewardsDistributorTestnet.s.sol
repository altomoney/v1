// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {UniversalRewardsDistributor} from "@morpho-org/universal-rewards-distributor/UniversalRewardsDistributor.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployUniversalRewardsDistributorTestnet is Script {
    function run() public {
        vm.startBroadcast();
        address universalRewardsDistributor =
            address(new UniversalRewardsDistributor(msg.sender, 1 days, bytes32(0), bytes32(0)));
        console.log("Universal Rewards Distributor deployed at", universalRewardsDistributor);
        vm.stopBroadcast();
    }
}
