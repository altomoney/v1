// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

/// @title Schedule Disable Permissionless frxUSD USM
/// @notice Generates scheduleBatch and executeBatch Safe txs to disable the public frxUSD USM
/// @dev Run with `forge script script/ScheduleDisablePermissionlessFrxUsdUsm.s.sol:ScheduleDisablePermissionlessFrxUsdUsmScript --rpc-url ethereum -vvvv`
contract ScheduleDisablePermissionlessFrxUsdUsmScript is Script {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant PERMISSIONLESS_FRXUSD_USM = 0x7b9468fB9f3146ec82ceB2Dd75e6a47F3EAd5f79;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    string constant SAFE_BATCH_NAME = "disable-permissionless-frxusd-usm";
    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        uint256 delay = TimelockController(payable(TIMELOCK)).getMinDelay();

        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory payloads = new bytes[](3);

        targets[0] = DUSD;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IDUSD.setMinterCeiling, (PERMISSIONLESS_FRXUSD_USM, 0));

        targets[1] = DUSD;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterStatus, (PERMISSIONLESS_FRXUSD_USM, false));

        targets[2] = PERMISSIONLESS_FRXUSD_USM;
        values[2] = 0;
        payloads[2] = abi.encodeCall(IUsm.updateExposureCap, (uint128(0)));

        bytes memory scheduleBatchData = abi.encodeCall(
            TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), bytes32(0), delay)
        );
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), bytes32(0)));

        console.log("=== Disable Permissionless frxUSD USM ===");
        console.log("Timelock:", TIMELOCK);
        console.log("Permissionless frxUSD USM:", PERMISSIONLESS_FRXUSD_USM);
        console.log("DUSD:", DUSD);
        console.log("Timelock delay (seconds):", delay);

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", SAFE_BATCH_NAME, "-schedule.json"),
            _buildSafeJson(string.concat(SAFE_BATCH_NAME, " - Schedule"), TIMELOCK, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", SAFE_BATCH_NAME, "-execute.json"),
            _buildSafeJson(string.concat(SAFE_BATCH_NAME, " - Execute"), TIMELOCK, executeBatchData)
        );

        console.log("\nSafe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json", SAFE_BATCH_NAME);
        console.log("  2. safe-tx-%s-execute.json", SAFE_BATCH_NAME);
    }

    function _buildSafeJson(string memory name, address to, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '","txBuilderVersion":"1.16.5"},"transactions":[{"to":"',
            vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data),
            '","contractMethod":null,"contractInputsValues":null}]}'
        );
    }
}
