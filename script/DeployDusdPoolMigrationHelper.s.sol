// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {DusdPoolMigrationHelper} from "script/helper/DusdPoolMigrationHelper.sol";

/// @title Deploy DusdPoolMigrationHelper
/// @notice Deploys `DusdPoolMigrationHelper` with treasury as owner for the DUSD/USDC → DUSD/frxUSD pool migration.
///
///         Usage:
///         forge script script/DeployDusdPoolMigrationHelper.s.sol:DeployDusdPoolMigrationHelperScript \
///           --rpc-url $ETH_RPC_URL --broadcast
contract DeployDusdPoolMigrationHelperScript is Script {
    address public constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    function run() public returns (DusdPoolMigrationHelper helper) {
        vm.startBroadcast();

        helper = new DusdPoolMigrationHelper(TREASURY);

        vm.stopBroadcast();

        console.log("=== DusdPoolMigrationHelper deployed ===");
        console.log("Owner (treasury):", TREASURY);
        console.log("Helper:", address(helper));
    }
}
