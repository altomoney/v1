// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {
    VELORA_AUGUSTUS_V6_MAINNET,
    NORDSTERN_ROUTER_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

uint256 constant DEPLOYMENT_ID = 1765364975;
string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
string constant BATCH_NAME = "leverage-swapper-set-swap-targets";

/// @title Set Velora Augustus and Nordstern Router as valid swap targets on all leverage swappers
/// @notice Generates timelock scheduleBatch and executeBatch Safe TX JSON files
/// @dev Run with: forge script script/SetLeverageSwapperSwapTargets.s.sol --rpc-url ethereum -vvv
contract SetLeverageSwapperSwapTargets is Script {
    function run() public {
        string memory addressesFile = string.concat(
            OUTPUT_DIR,
            "/ethereum-mainnet-",
            vm.toString(block.chainid),
            "-",
            vm.toString(DEPLOYMENT_ID),
            "/addresses.json"
        );

        string memory json = vm.readFile(addressesFile);
        address timelock = vm.parseJsonAddress(json, ".contracts.timelock");

        address[] memory swappers = _loadLeverageSwappers(json);
        address[] memory swapTargets = new address[](2);
        swapTargets[0] = VELORA_AUGUSTUS_V6_MAINNET;
        swapTargets[1] = NORDSTERN_ROUTER_MAINNET;

        uint256 actionCount = swappers.length * swapTargets.length;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

        address[] memory targets = new address[](actionCount);
        uint256[] memory values = new uint256[](actionCount);
        bytes[] memory payloads = new bytes[](actionCount);

        uint256 idx;
        for (uint256 i = 0; i < swappers.length; i++) {
            for (uint256 j = 0; j < swapTargets.length; j++) {
                targets[idx] = swappers[i];
                values[idx] = 0;
                payloads[idx] =
                    abi.encodeCall(AltoLeverageSwapperMultiTarget.setValidSwapTarget, (swapTargets[j], true));
                idx++;
            }
        }

        _writeSafeTimelockBatchJson(BATCH_NAME, timelock, targets, values, payloads, minDelay);

        console.log("Loaded addresses from:", addressesFile);
        console.log("Timelock:", timelock);
        console.log("Velora Augustus V6:", VELORA_AUGUSTUS_V6_MAINNET);
        console.log("Nordstern Router:", NORDSTERN_ROUTER_MAINNET);
        console.log("Leverage swappers:", swappers.length);
        console.log("Timelock actions:", actionCount);
        console.log("Timelock delay:", minDelay);
    }

    function _loadLeverageSwappers(string memory json) internal pure returns (address[] memory swappers) {
        string[12] memory keys = [
            "wethLeverageSwapper",
            "wstethLeverageSwapper",
            "rethLeverageSwapper",
            "methLeverageSwapper",
            "tbtcLeverageSwapper",
            "wbtcBorrowLeverageSwapper",
            "cbbtcBorrowLeverageSwapper",
            "susdeBorrowLeverageSwapper",
            "syrupUsdcBorrowLeverageSwapper",
            "paxgBorrowLeverageSwapper",
            "susdeMintLeverageSwapper",
            "syrupUsdcMintLeverageSwapper"
        ];

        swappers = new address[](12);
        for (uint256 i = 0; i < 12; i++) {
            swappers[i] = vm.parseJsonAddress(json, string.concat(".contracts.", keys[i]));
        }
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
