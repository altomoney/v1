// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Generate Timelock Calldata for Rebalancing DUSD Across Borrow Markets
/// @notice Remove 50k DUSD from sUSDe borrow market, supply 50k DUSD to PAXG borrow market. Logs scheduleBatch and executeBatch.
/// @dev All operations are executed as timelock (supply position owner). Run with --rpc-url to fetch timelock delay.
contract GenerateRebalanceDusdBorrowMarketsTimelockTransactions is Script {
    uint256 constant REBALANCE_AMOUNT = 50_000 ether; // 50k DUSD (18 decimals)

    string constant DEFAULT_ADDRESSES_PATH =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    address constant MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    function run() public view {
        string memory json = vm.readFile(vm.envOr("ADDRESSES_JSON", DEFAULT_ADDRESSES_PATH));

        address timelock = vm.parseJsonAddress(json, ".contracts.timelock");
        address dusd = vm.parseJsonAddress(json, ".contracts.dusd");
        address susdeBorrowMarket = vm.parseJsonAddress(json, ".contracts.susdeBorrowMarket");
        address paxgBorrowMarket = vm.parseJsonAddress(json, ".contracts.paxgBorrowMarket");
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();

        if (paxgBorrowMarket == address(0)) {
            console.log("WARNING: paxgBorrowMarket is address(0) in deployment file.");
        }

        // 1. removeSupply from sUSDe (DUSD -> timelock), 2. approve DUSD for PAXG market, 3. addSupply to PAXG
        address[] memory targets = new address[](3);
        targets[0] = susdeBorrowMarket;
        targets[1] = dusd;
        targets[2] = paxgBorrowMarket;

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory payloads = new bytes[](3);
        payloads[0] = abi.encodeCall(IMarketBase.removeSupply, (REBALANCE_AMOUNT, uint256(0), MULTISIG, MULTISIG));
        payloads[1] = abi.encodeCall(IERC20.approve, (paxgBorrowMarket, REBALANCE_AMOUNT));
        payloads[2] = abi.encodeCall(IMarketBase.addSupply, (REBALANCE_AMOUNT, uint256(0), MULTISIG));

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        console.log("=== Rebalance DUSD Borrow Markets - Timelock ===");
        console.log("Remove 50k DUSD from sUSDe, supply 50k DUSD to PAXG.");
        console.log("Timelock:", timelock);
        console.log("Withdrawal recipient (multisig):", MULTISIG);
        console.log("susdeBorrowMarket:", susdeBorrowMarket);
        console.log("dusd:", dusd);
        console.log("paxgBorrowMarket:", paxgBorrowMarket);
        console.log("Amount:", REBALANCE_AMOUNT);
        console.log("Delay (seconds):", delay);
        console.log("--- Step 1: Propose - scheduleBatch ---");
        console.log("To:", timelock);
        console.logBytes(scheduleBatchData);
        console.log("--- Step 2: Execute - executeBatch (after delay) ---");
        console.log("To:", timelock);
        console.logBytes(executeBatchData);
    }
}
