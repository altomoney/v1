// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";

/// @title Schedule and Execute setIrmConfig for sSUDe and syrupUSDC Markets
/// @notice Generates schedule and execute transaction data to update initialRateAtTarget to 4% for both markets
contract ScheduleSetIrmConfig is Script {
    // Addresses from addresses.json
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant SUSDE_BORROW_MARKET_IRM = 0x0fA28df153dcdE055996ecdf6B9797aAC9bed1CC;
    address constant SYRUP_USDC_BORROW_MARKET_IRM = 0xAf3049615aF02785a02293C8EdcB460aBEA7791C;

    // New initialRateAtTarget: 4% per year = 0.04 ether / int256(365 days)
    int256 constant NEW_INITIAL_RATE_AT_TARGET = 0.04 ether / int256(365 days);

    function run() public {
        console.log("=== Schedule and Execute setIrmConfig Batch ===");
        console.log("Timelock Address:", TIMELOCK);
        console.log("");

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        uint256 delay = timelock.getMinDelay();
        console.log("Timelock Delay (seconds):", delay);
        console.log("");

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);

        // Process sSUDe market
        console.log("=== sSUDe Borrow Market IRM ===");
        console.log("IRM Address:", SUSDE_BORROW_MARKET_IRM);
        payloads[0] = _getSetIrmConfigPayload(SUSDE_BORROW_MARKET_IRM);
        targets[0] = SUSDE_BORROW_MARKET_IRM;
        values[0] = 0;
        console.log("");

        // Process syrupUSDC market
        console.log("=== syrupUSDC Borrow Market IRM ===");
        console.log("IRM Address:", SYRUP_USDC_BORROW_MARKET_IRM);
        payloads[1] = _getSetIrmConfigPayload(SYRUP_USDC_BORROW_MARKET_IRM);
        targets[1] = SYRUP_USDC_BORROW_MARKET_IRM;
        values[1] = 0;
        console.log("");

        // Generate batch transaction data
        _logBatchTransactionData(targets, values, payloads, delay);
    }

    function _getSetIrmConfigPayload(address irmAddress) internal view returns (bytes memory) {
        // Fetch current config (returns tuple of 6 int256 values)
        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = AdaptiveCurveIrm(irmAddress).irmConfig();

        console.log("Current Config:");
        console.log("  curveSteepness:", uint256(curveSteepness));
        console.log("  adjustmentSpeed:", uint256(adjustmentSpeed));
        console.log("  targetUtilization:", uint256(targetUtilization));
        console.log("  initialRateAtTarget:", uint256(initialRateAtTarget));
        console.log("  minRateAtTarget:", uint256(minRateAtTarget));
        console.log("  maxRateAtTarget:", uint256(maxRateAtTarget));
        console.log("");

        console.log("New Config:");
        console.log("  curveSteepness:", uint256(curveSteepness));
        console.log("  adjustmentSpeed:", uint256(adjustmentSpeed));
        console.log("  targetUtilization:", uint256(targetUtilization));
        console.log("  initialRateAtTarget:", uint256(NEW_INITIAL_RATE_AT_TARGET));
        console.log("  minRateAtTarget:", uint256(minRateAtTarget));
        console.log("  maxRateAtTarget:", uint256(maxRateAtTarget));

        // Encode setIrmConfig call with new config (inline struct creation)
        return abi.encodeWithSelector(
            AdaptiveCurveIrm.setIrmConfig.selector,
            AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                curveSteepness: curveSteepness,
                adjustmentSpeed: adjustmentSpeed,
                targetUtilization: targetUtilization,
                initialRateAtTarget: NEW_INITIAL_RATE_AT_TARGET,
                minRateAtTarget: minRateAtTarget,
                maxRateAtTarget: maxRateAtTarget
            })
        );
    }

    function _logBatchTransactionData(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal view {
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        console.log("=== BATCH TRANSACTION DATA ===");
        console.log("Timelock:", TIMELOCK);
        console.log("Delay (seconds):", delay);
        console.log("Number of operations:", targets.length);
        console.log("");
        console.log("--- Batch Contents ---");
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("Operation", i);
            console.log("  target:", targets[i]);
            console.log("  value:", values[i]);
            console.log("  payload:");
            console.logBytes(payloads[i]);
        }
        console.log("");
        console.log("--- Step 1: ScheduleBatch (submit to multisig now) ---");
        console.log("Call timelock at:", TIMELOCK);
        bytes memory scheduleBatchData = abi.encodeWithSelector(
            TimelockController.scheduleBatch.selector, targets, values, payloads, predecessor, salt, delay
        );
        console.logBytes(scheduleBatchData);
        console.log("");
        console.log("--- Step 2: ExecuteBatch (submit to multisig after delay) ---");
        console.log("Call timelock at:", TIMELOCK);
        bytes memory executeBatchData = abi.encodeWithSelector(
            TimelockController.executeBatch.selector, targets, values, payloads, predecessor, salt
        );
        console.logBytes(executeBatchData);
        console.log("");
        console.log("==========================================");
    }
}
