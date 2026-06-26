// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";

/// @title Grant USM Roles to Timelock
/// @notice Generates Safe TX Builder JSONs for scheduleBatch/executeBatch to grant TOKEN_RESCUER_ROLE and
///         LIQUIDATOR_ROLE to the timelock on all PSMs registered in UsmRegistry.
/// @dev Run against mainnet fork so UsmRegistry.getUsmList() and timelock.getMinDelay() resolve:
///      forge script script/GrantUsmRolesToTimelock.s.sol --fork-url ethereum
contract GrantUsmRolesToTimelock is Script {
    bytes32 internal constant TOKEN_RESCUER_ROLE = keccak256("TOKEN_RESCUER_ROLE");
    bytes32 internal constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    address internal constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address internal constant USM_REGISTRY = 0xAD5620e10C33918E2C6A2E8E53325bf98c548E5e;

    string internal constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() external {
        address[] memory usms = IUsmRegistry(USM_REGISTRY).getUsmList();
        require(usms.length > 0, "No USMs in registry");

        uint256 txCount = usms.length * 2;
        address[] memory targets = new address[](txCount);
        uint256[] memory values = new uint256[](txCount);
        bytes[] memory payloads = new bytes[](txCount);

        uint256 txIndex;
        for (uint256 i; i < usms.length; ++i) {
            console.log("USM:", usms[i]);

            targets[txIndex] = usms[i];
            values[txIndex] = 0;
            payloads[txIndex] = abi.encodeCall(AccessControl.grantRole, (TOKEN_RESCUER_ROLE, TIMELOCK));
            txIndex++;

            targets[txIndex] = usms[i];
            values[txIndex] = 0;
            payloads[txIndex] = abi.encodeCall(AccessControl.grantRole, (LIQUIDATOR_ROLE, TIMELOCK));
            txIndex++;
        }

        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();
        _writeSafeTimelockBatchJson(
            "usm-grant-rescuer-liquidator-roles-to-timelock", TIMELOCK, targets, values, payloads, minDelay
        );
    }

    function _writeSafeTimelockBatchJson(
        string memory name,
        address timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal {
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-schedule.json"),
            _buildSafeJson(string.concat(name, " - Schedule"), timelock, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-execute.json"),
            _buildSafeJson(string.concat(name, " - Execute"), timelock, executeBatchData)
        );

        console.log("Safe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json  (propose)", name);
        console.log("  2. safe-tx-%s-execute.json   (execute after delay)", name);
    }

    function _buildSafeJson(string memory name, address to, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '"},"transactions":[{"to":"',
            vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data),
            '"}]}'
        );
    }
}
