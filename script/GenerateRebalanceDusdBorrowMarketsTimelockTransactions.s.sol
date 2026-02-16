// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Generate Safe Transaction Builder JSON for Rebalancing DUSD Across Borrow Markets
/// @notice Remove 50k DUSD from sUSDe borrow market, supply 50k DUSD to PAXG borrow market.
/// @dev Outputs a JSON file importable into Safe{Wallet} Transaction Builder. Multisig is the supply position owner.
contract GenerateRebalanceDusdBorrowMarketsTimelockTransactions is Script {
    uint256 constant REBALANCE_AMOUNT = 50_000 ether; // 50k DUSD (18 decimals)

    string constant DEFAULT_ADDRESSES_PATH =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    address constant MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    function run() public {
        string memory json = vm.readFile(vm.envOr("ADDRESSES_JSON", DEFAULT_ADDRESSES_PATH));

        address dusd = vm.parseJsonAddress(json, ".contracts.dusd");
        address susdeBorrowMarket = vm.parseJsonAddress(json, ".contracts.susdeBorrowMarket");
        address paxgBorrowMarket = vm.parseJsonAddress(json, ".contracts.paxgBorrowMarket");

        if (paxgBorrowMarket == address(0)) {
            console.log("WARNING: paxgBorrowMarket is address(0) in deployment file.");
        }

        bytes memory removeSupplyData =
            abi.encodeCall(IMarketBase.removeSupply, (REBALANCE_AMOUNT, uint256(0), MULTISIG, MULTISIG));
        bytes memory approveData = abi.encodeCall(IERC20.approve, (paxgBorrowMarket, REBALANCE_AMOUNT));
        bytes memory addSupplyData = abi.encodeCall(IMarketBase.addSupply, (REBALANCE_AMOUNT, uint256(0), MULTISIG));

        string memory safeBatchJson = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"Rebalance DUSD Borrow Markets"},"transactions":[',
            _toJsonTx(susdeBorrowMarket, removeSupplyData),
            ",",
            _toJsonTx(dusd, approveData),
            ",",
            _toJsonTx(paxgBorrowMarket, addSupplyData),
            "]}"
        );

        string memory outputPath = "contracts/deployments/ethereum-mainnet/output/safe-tx-rebalance-dusd.json";
        vm.writeFile(outputPath, safeBatchJson);

        console.log("=== Rebalance DUSD Borrow Markets ===");
        console.log("Multisig (sender / supply owner):", MULTISIG);
        console.log("susdeBorrowMarket:", susdeBorrowMarket);
        console.log("dusd:", dusd);
        console.log("paxgBorrowMarket:", paxgBorrowMarket);
        console.log("Amount:", REBALANCE_AMOUNT);
        console.log("");
        console.log("Safe Transaction Builder JSON written to:", outputPath);
    }

    function _toJsonTx(address to, bytes memory data) internal pure returns (string memory) {
        return string.concat('{"to":"', vm.toString(to), '","value":"0","data":"', vm.toString(data), '"}');
    }
}
