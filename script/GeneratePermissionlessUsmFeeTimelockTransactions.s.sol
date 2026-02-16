// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Generate Timelock Calldata for Updating Permissionless USM Fee to 0.05%
/// @notice Outputs scheduleBatch and executeBatch calldata to call setFee(5, 5) on FixedFeeStrategy (5 bps = 0.05% each way).
/// @dev CONFIGURATOR_ROLE is timelock. Addresses from addresses.json. Run with --rpc-url to fetch timelock delay.
contract GeneratePermissionlessUsmFeeTimelockTransactions is Script {
    /// 0.05% in basis points (PERCENTAGE_PRECISION = 10000 in FixedFeeStrategy)
    uint256 constant NEW_BUY_FEE_BPS = 5;
    uint256 constant NEW_SELL_FEE_BPS = 5;

    string constant DEFAULT_ADDRESSES_PATH =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    function run() public view {
        string memory json = vm.readFile(vm.envOr("ADDRESSES_JSON", DEFAULT_ADDRESSES_PATH));

        address timelock = vm.parseJsonAddress(json, ".contracts.timelock");
        address fixedFeeStrategy = vm.parseJsonAddress(json, ".contracts.permissionlessUsmFixedFeeStrategy");
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();

        address[] memory targets = new address[](1);
        targets[0] = fixedFeeStrategy;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(FixedFeeStrategy.setFee, (NEW_BUY_FEE_BPS, NEW_SELL_FEE_BPS));

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        console.log("=== Permissionless USM Fee Update - Timelock ===");
        console.log("Target (permissionlessUsmFixedFeeStrategy):", fixedFeeStrategy);
        console.log("New fee: buyFee=5 bps (0.05%), sellFee=5 bps (0.05%)");
        console.log("Timelock:", timelock);
        console.log("Delay (seconds):", delay);
        console.log("--- Step 1: Propose - scheduleBatch ---");
        console.log("To:", timelock);
        console.logBytes(scheduleBatchData);
        console.log("--- Step 2: Execute - executeBatch (after delay) ---");
        console.log("To:", timelock);
        console.logBytes(executeBatchData);
    }
}
