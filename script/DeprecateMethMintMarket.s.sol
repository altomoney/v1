// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

/// @title Deprecate mETH Mint Market
/// @notice Generates Safe wallet calldata to lower the mETH mint market DUSD minter ceiling to 1000 DUSD.
///         DUSD owner is AltoTimelockController, so governance must schedule then execute after the delay.
///
///         Flow (2 transactions via Safe):
///           1. timelock.scheduleBatch — queue setMinterCeiling on DUSD
///           2. timelock.executeBatch  — execute after min delay elapses
///
///         forge script script/DeprecateMethMintMarket.s.sol:DeprecateMethMintMarketScript --fork-url $ETH_RPC_URL
contract DeprecateMethMintMarketScript is Script {
    string private constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string private constant SAFE_TX_NAME = "deprecate-meth-mint-market";

    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address public constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    uint256 public constant NEW_MINTER_CEILING = 1000 ether;

    function run() public {
        (, uint256 currentCeiling) = IDUSD(DUSD).minterConfig(METH_MARKET);
        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();

        console.log("=== Deprecate mETH Mint Market ===");
        console.log("DUSD:", DUSD);
        console.log("Timelock:", TIMELOCK);
        console.log("mETH mint market:", METH_MARKET);
        console.log("Current minter ceiling:", currentCeiling);
        console.log("New minter ceiling:", NEW_MINTER_CEILING);
        console.log("Timelock min delay (seconds):", minDelay);
        console.log("");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildBatch();
        _logBatch("Schedule", targets, values, payloads, minDelay);
        _writeTimelockJson(SAFE_TX_NAME, targets, values, payloads, minDelay);
    }

    function _buildBatch()
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](1);
        values = new uint256[](1);
        payloads = new bytes[](1);

        targets[0] = DUSD;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IDUSD.setMinterCeiling, (METH_MARKET, NEW_MINTER_CEILING));
    }

    function _logBatch(
        string memory phase,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal pure {
        console.log(string.concat("--- ", phase, " batch ---"));
        for (uint256 i = 0; i < targets.length; i++) {
            console.log(string.concat("Tx ", vm.toString(i + 1), " | DUSD.setMinterCeiling(mETH market, 1000 DUSD)"));
            console.log("Target:", targets[i]);
            console.log("Value:", values[i]);
            console.logBytes(payloads[i]);
        }
        if (delay > 0) {
            console.log("Delay (seconds):", delay);
        }
        console.log("");
    }

    function _writeTimelockJson(
        string memory name,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal {
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleBatchData = abi.encodeCall(
            TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay)
        );
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        string memory scheduleFile = string.concat(OUTPUT_DIR, "/safe-tx-", name, "-schedule.json");
        string memory executeFile = string.concat(OUTPUT_DIR, "/safe-tx-", name, "-execute.json");

        vm.writeFile(scheduleFile, _buildSafeJson(string.concat(name, " - Schedule"), TIMELOCK, scheduleBatchData));
        vm.writeFile(executeFile, _buildSafeJson(string.concat(name, " - Execute"), TIMELOCK, executeBatchData));

        console.log("Safe TX Builder JSONs written:");
        console.log("  1.", scheduleFile);
        console.log("  2.", executeFile);
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
