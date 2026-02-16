// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Generate Safe Transaction Builder JSON for Updating IRM Config on Borrow Markets and Permissionless USM Fee
/// @notice IRM: curveSteepness=2, adjustmentSpeed=25/YEAR. USM fee: 5 bps each way.
/// @dev Outputs two JSON files: one for scheduleBatch, one for executeBatch (after delay). Run with --rpc-url.
contract GenerateBorrowMarketsIrmConfigTimelockTransactions is Script {
    int256 internal constant YEAR = 365 days;

    /// 0.05% in basis points (PERCENTAGE_PRECISION = 10000 in FixedFeeStrategy)
    uint256 constant NEW_BUY_FEE_BPS = 5;
    uint256 constant NEW_SELL_FEE_BPS = 5;

    uint256 constant NUM_IRM_TARGETS = 2;
    uint256 constant NUM_USM_TARGETS = 1;
    uint256 constant TOTAL_TARGETS = NUM_IRM_TARGETS + NUM_USM_TARGETS;

    string constant DEFAULT_ADDRESSES_PATH =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    function run() public {
        string memory json = vm.readFile(DEFAULT_ADDRESSES_PATH);

        address timelock = vm.parseJsonAddress(json, ".contracts.timelock");
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();

        address[] memory targets = new address[](TOTAL_TARGETS);
        uint256[] memory values = new uint256[](TOTAL_TARGETS);
        bytes[] memory payloads = new bytes[](TOTAL_TARGETS);

        // --- IRM config updates ---
        targets[0] = vm.parseJsonAddress(json, ".contracts.susdeBorrowMarketIrm");
        targets[1] = vm.parseJsonAddress(json, ".contracts.syrupUsdcBorrowMarketIrm");

        for (uint256 i = 0; i < NUM_IRM_TARGETS; i++) {
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

        // --- Permissionless USM fee update ---
        address fixedFeeStrategy = vm.parseJsonAddress(json, ".contracts.permissionlessUsmFixedFeeStrategy");
        targets[NUM_IRM_TARGETS] = fixedFeeStrategy;
        values[NUM_IRM_TARGETS] = 0;
        payloads[NUM_IRM_TARGETS] = abi.encodeCall(FixedFeeStrategy.setFee, (NEW_BUY_FEE_BPS, NEW_SELL_FEE_BPS));

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        // --- Write Safe TX Builder JSONs ---
        string memory outputDir = "contracts/deployments/ethereum-mainnet/output";
        vm.writeFile(
            string.concat(outputDir, "/safe-tx-irm-fee-schedule.json"),
            _buildSafeJson("IRM + Fee Update - Schedule", timelock, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(outputDir, "/safe-tx-irm-fee-execute.json"),
            _buildSafeJson("IRM + Fee Update - Execute", timelock, executeBatchData)
        );

        // --- Console summary ---
        console.log("=== Borrow Markets IRM Config + USM Fee Update ===");
        console.log("Timelock:", timelock);
        console.log("Delay (seconds):", delay);
        console.log("");
        console.log("IRM update: curveSteepness=2 ether, adjustmentSpeed=25/YEAR; rest from on-chain.");
        console.log("  susdeBorrowMarketIrm:", targets[0]);
        console.log("  syrupUsdcBorrowMarketIrm:", targets[1]);
        console.log("");
        console.log("USM fee update: buyFee=5 bps, sellFee=5 bps");
        console.log("  permissionlessUsmFixedFeeStrategy:", fixedFeeStrategy);
        console.log("");
        console.log("Safe TX Builder JSONs written:");
        console.log("  1. safe-tx-irm-fee-schedule.json  (propose)");
        console.log("  2. safe-tx-irm-fee-execute.json   (execute after delay)");
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
