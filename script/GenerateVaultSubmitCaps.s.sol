// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";

/// @title GenerateVaultSubmitCaps
/// @notice Generates Safe TX Builder JSON files (schedule + execute) to raise each borrow market
///         cap on the DUSD vault to 80_000 ether via the timelock.
///
/// Run:
///   forge script script/GenerateVaultSubmitCaps.s.sol:GenerateVaultSubmitCaps --rpc-url ethereum
contract GenerateVaultSubmitCaps is Script {
    address constant VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

    // ── Borrow markets (supply queue order: syrupUSDC → sUSDe → PAXG → WBTC → cbBTC) ──
    address constant SYRUPUSDC_BORROW = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant SUSDE_BORROW = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address constant PAXG_BORROW = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817;
    address constant WBTC_BORROW = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
    address constant CBBTC_BORROW = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;

    uint256 constant CAP = 80_000 ether;

    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        uint256 delay = TimelockController(payable(TIMELOCK)).getMinDelay();

        address[5] memory markets = [SYRUPUSDC_BORROW, SUSDE_BORROW, PAXG_BORROW, WBTC_BORROW, CBBTC_BORROW];

        address[] memory targets = new address[](5);
        uint256[] memory values = new uint256[](5);
        bytes[] memory payloads = new bytes[](5);

        for (uint256 i; i < 5; ++i) {
            targets[i] = VAULT;
            payloads[i] = abi.encodeCall(IAltoVaultBase.submitCap, (markets[i], CAP));
        }

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-vault-submit-caps-schedule.json"),
            _buildSafeJson("vault-submit-caps - Schedule", TIMELOCK, scheduleData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-vault-submit-caps-execute.json"),
            _buildSafeJson("vault-submit-caps - Execute", TIMELOCK, executeData)
        );

        console.log("Vault: %s", VAULT);
        console.log("Timelock: %s  (delay: %s s)", TIMELOCK, vm.toString(delay));
        console.log("Cap per market: %s ether", vm.toString(CAP / 1 ether));
        console.log("\nMarkets:");
        string[5] memory names = ["syrupUSDC", "sUSDe", "PAXG", "WBTC", "cbBTC"];
        for (uint256 i; i < 5; ++i) {
            console.log("  %s : %s", names[i], markets[i]);
        }
        console.log("\nSafe TX JSONs written:");
        console.log("  safe-tx-vault-submit-caps-schedule.json  (propose)");
        console.log("  safe-tx-vault-submit-caps-execute.json   (execute after delay)");
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
