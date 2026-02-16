// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Generate Timelock Calldata for Updating IRM Config on Borrow Markets
/// @notice Outputs scheduleBatch and executeBatch calldata. New config = old config (from chain) with curveSteepness=2, adjustmentSpeed=25/YEAR.
/// @dev Run with --rpc-url to fetch current IRM config from chain. Addresses from addresses.json.
contract GenerateBorrowMarketsIrmConfigTimelockTransactions is Script {
    int256 internal constant YEAR = 365 days;

    string constant DEFAULT_ADDRESSES_PATH =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    function run() public view {
        string memory json = vm.readFile(vm.envOr("ADDRESSES_JSON", DEFAULT_ADDRESSES_PATH));

        address timelock = vm.parseJsonAddress(json, ".contracts.timelock");
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();
        address[] memory targets = new address[](4);
        targets[0] = vm.parseJsonAddress(json, ".contracts.susdeBorrowMarketIrm");
        targets[1] = vm.parseJsonAddress(json, ".contracts.syrupUsdcBorrowMarketIrm");
        targets[2] = vm.parseJsonAddress(json, ".contracts.wbtcBorrowMarketIrm");
        targets[3] = vm.parseJsonAddress(json, ".contracts.cbbtcBorrowMarketIrm");

        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);
        for (uint256 i = 0; i < 4; i++) {
            values[i] = 0;
            AdaptiveCurveIrm irm = AdaptiveCurveIrm(targets[i]);
            (
                int256 curveSteepness,
                int256 adjustmentSpeed,
                int256 targetUtilization,
                int256 initialRateAtTarget,
                int256 minRateAtTarget,
                int256 maxRateAtTarget
            ) = irm.irmConfig();
            AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory oldConfig = AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                curveSteepness: curveSteepness,
                adjustmentSpeed: adjustmentSpeed,
                targetUtilization: targetUtilization,
                initialRateAtTarget: initialRateAtTarget,
                minRateAtTarget: minRateAtTarget,
                maxRateAtTarget: maxRateAtTarget
            });
            payloads[i] = abi.encodeCall(AdaptiveCurveIrm.setIrmConfig, (_newConfigFromOld(oldConfig)));
        }

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        _logOutput(timelock, targets, delay, scheduleBatchData, executeBatchData);
    }

    /// @dev Old config with curveSteepness = 2 ether and adjustmentSpeed = 25 ether / YEAR.
    function _newConfigFromOld(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory oldConfig)
        internal
        pure
        returns (AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory)
    {
        return AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 2 ether,
            adjustmentSpeed: 25 ether / YEAR,
            targetUtilization: oldConfig.targetUtilization,
            initialRateAtTarget: oldConfig.initialRateAtTarget,
            minRateAtTarget: oldConfig.minRateAtTarget,
            maxRateAtTarget: oldConfig.maxRateAtTarget
        });
    }

    function _logOutput(
        address timelock,
        address[] memory targets,
        uint256 delay,
        bytes memory scheduleBatchData,
        bytes memory executeBatchData
    ) internal pure {
        console.log("=== Borrow Markets IRM Config Update - Timelock Batch ===");
        console.log("Timelock:", timelock);
        console.log("Delay (seconds):", delay);
        console.log("New config: curveSteepness=2 ether, adjustmentSpeed=25/YEAR; rest from on-chain.");
        console.log("IRM targets: susde, syrupUsdc, wbtc, cbbtc");
        console.log("  ", targets[0]);
        console.log("  ", targets[1]);
        console.log("  ", targets[2]);
        console.log("  ", targets[3]);
        console.log("--- Step 1: Propose - scheduleBatch ---");
        console.log("To:", timelock);
        console.logBytes(scheduleBatchData);
        console.log("--- Step 2: Execute - executeBatch (after delay) ---");
        console.log("To:", timelock);
        console.logBytes(executeBatchData);
    }

}
