// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";

/// @title Freeze tBTC Mint Market
/// @notice Generates Safe wallet calldata to freeze the tBTC mint market.
///         Freezer/pauser is the Safe multisig; no timelock required.
///
///         forge script script/PauseTbtcMintMarket.s.sol:PauseTbtcMintMarketScript --fork-url $ETH_RPC_URL
contract PauseTbtcMintMarketScript is Script {
    string private constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string private constant SAFE_TX_NAME = "pause-tbtc-market";

    address public constant FREEZER_MULTISIG = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;
    address public constant TBTC_MARKET = 0xE17F10f8535336143d4F2FE304f3Dcf7B23671e1;

    function run() public {
        bool isFrozen = IPausable(TBTC_MARKET).paused(FROZEN_TYPE);
        bool isPauser = Pausable(TBTC_MARKET).pausers(FREEZER_MULTISIG, FROZEN_TYPE);

        console.log("=== Freeze tBTC Mint Market ===");
        console.log("Freezer multisig:", FREEZER_MULTISIG);
        console.log("tBTC mint market:", TBTC_MARKET);
        console.log("Currently frozen:", isFrozen);
        console.log("Multisig is freezer:", isPauser);
        console.log("");

        (address[] memory targets, bytes[] memory payloads) = _buildTransactions();
        _logTransactions(targets, payloads);
        _writeSafeBatchJson(SAFE_TX_NAME, targets, payloads);
    }

    function _buildTransactions() internal pure returns (address[] memory targets, bytes[] memory payloads) {
        targets = new address[](1);
        payloads = new bytes[](1);

        targets[0] = TBTC_MARKET;
        payloads[0] = abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true));
    }

    function _logTransactions(address[] memory targets, bytes[] memory payloads) internal pure {
        for (uint256 i = 0; i < targets.length; i++) {
            _logHeader(i + 1, _txLabel(i + 1), targets[i]);
            console.logBytes(payloads[i]);
        }
    }

    function _txLabel(uint256 txNum) internal pure returns (string memory) {
        if (txNum == 1) return "freeze tBTC mint market (FROZEN_TYPE)";
        return "unknown";
    }

    function _writeSafeBatchJson(string memory name, address[] memory targets, bytes[] memory payloads) internal {
        string memory fileName = string.concat(OUTPUT_DIR, "/safe-tx-", name, ".json");
        vm.writeFile(fileName, _buildSafeBatchJson(name, targets, payloads));
        console.log("");
        console.log("Safe TX Builder JSON written:");
        console.log(" ", fileName);
    }

    function _buildSafeBatchJson(string memory name, address[] memory targets, bytes[] memory payloads)
        internal
        pure
        returns (string memory)
    {
        string memory json =
            string.concat('{"version":"1.0","chainId":"1","meta":{"name":"', name, '"},"transactions":[');

        for (uint256 i = 0; i < targets.length; i++) {
            uint256 txNum = i + 1;
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(targets[i]),
                '","value":"0","data":"',
                vm.toString(payloads[i]),
                '","label":"Tx ',
                vm.toString(txNum),
                " | ",
                _txLabel(txNum),
                '"}'
            );
        }

        return string.concat(json, "]}");
    }

    function _logHeader(uint256 txNum, string memory label, address to) internal pure {
        console.log(string.concat("--- Tx ", vm.toString(txNum), " | ", label, " ---"));
        console.log("To:", to);
    }
}
