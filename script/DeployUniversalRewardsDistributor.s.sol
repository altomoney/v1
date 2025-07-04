// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {UniversalRewardsDistributor} from "universal-rewards-distributor/UniversalRewardsDistributor.sol";
import {Script} from "forge-std/Script.sol";

contract DeployUniversalRewardsDistributor is Script {
    function run() public {
        vm.startBroadcast();
        new UniversalRewardsDistributor(msg.sender, 2 days, bytes32(0), bytes32(0));
        vm.stopBroadcast();
    }
}