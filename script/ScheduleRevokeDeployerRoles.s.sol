// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Execute Batch: Revoke Deployer Roles from Timelock
/// @notice Generates executeBatch transaction data to revoke PROPOSER_ROLE, EXECUTOR_ROLE, CANCELLER_ROLE, and DEFAULT_ADMIN_ROLE from deployer
/// @dev This script generates the executeBatch transaction created in _revokeTimelockRolesFromDeployer in POST phase
contract ScheduleRevokeDeployerRoles is Script {
    function run() public {
        address timelock = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

        address deployer = 0xBA5eD2B1234274a0fFE44E717119C0ECa04703ed;

        console.log("=== Execute Batch: Revoke Deployer Roles ===");
        console.log("Timelock Address:", timelock);
        console.log("Deployer Address:", deployer);

        AltoTimelockController timelockContract = AltoTimelockController(payable(timelock));

        // Get the 4 roles to revoke
        bytes32[] memory roles = new bytes32[](4);
        roles[0] = timelockContract.PROPOSER_ROLE();
        roles[1] = timelockContract.EXECUTOR_ROLE();
        roles[2] = timelockContract.CANCELLER_ROLE();
        roles[3] = timelockContract.DEFAULT_ADMIN_ROLE();

        console.log("\nRoles to revoke:");
        console.logBytes32(roles[0]);
        console.logBytes32(roles[1]);
        console.logBytes32(roles[2]);
        console.logBytes32(roles[3]);

        // Prepare batch transaction data (same as in _revokeTimelockRolesFromDeployer)
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);

        for (uint256 i = 0; i < 4; i++) {
            targets[i] = address(timelockContract);
            values[i] = 0;
            payloads[i] = abi.encodeWithSelector(AccessControl.revokeRole.selector, roles[i], deployer);
        }

        console.log("\n=== TRANSACTION DATA FOR SAFE WALLET ===");
        console.log("\n--- Execute Batch: Revoke Deployer Roles ---");
        console.log("To:", timelock);
        console.log("Value: 0");
        console.log("Function: executeBatch");
        console.log("Targets:");
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("  [", i, "]:", targets[i]);
        }
        console.log("Values:");
        for (uint256 i = 0; i < values.length; i++) {
            console.log("  [", i, "]:", values[i]);
        }
        console.log("Payloads:");
        for (uint256 i = 0; i < payloads.length; i++) {
            console.log("  [", i, "]:");
            console.logBytes(payloads[i]);
        }
        console.log("Predecessor: bytes32(0)");
        console.log("Salt: bytes32(0)");

        // Encode the executeBatch call
        bytes memory executeBatchData = abi.encodeWithSelector(
            timelockContract.executeBatch.selector, targets, values, payloads, bytes32(0), bytes32(0)
        );

        console.log("\n--- Encoded Transaction Data ---");
        console.logBytes(executeBatchData);

        console.log("\n=== INSTRUCTIONS ===");
        console.log("1. Ensure the batch transaction has been scheduled and the delay period has passed");
        console.log("2. Execute this transaction from an executor account");
        console.log("3. This will revoke all 4 roles (PROPOSER, EXECUTOR, CANCELLER, DEFAULT_ADMIN) from the deployer");
    }
}

