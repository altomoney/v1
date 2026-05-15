// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";

/// @title Deprecate Permissionless USDC USM
/// @notice Two-phase deprecation of the permissionless USDC PSM.
///
///   PHASE 1 — Treasury batch (6 txs, no timelock)
///     Drains all USDC liquidity from the USDC PSM by routing through the frxUSD PSM:
///       1. Approve USDC  → Frax Custodian
///       2. Deposit USDC  → Frax Custodian   (1:1 → frxUSD)
///       3. Approve frxUSD → frxUSD PSM
///       4. Sell frxUSD   → frxUSD PSM        (→ DUSD)
///       5. Approve DUSD  → USDC PSM
///       6. Buy USDC      ← USDC PSM          (spend DUSD, receive USDC)
///
///   PHASE 2 — Timelock cleanup (scheduleBatch + executeBatch Safe JSONs written to disk)
///     After the PSM is empty, revoke all protocol-level access:
///       1. DUSD.setMinterStatus(USDC_PSM, false)
///       2. DUSD.setMinterCeiling(USDC_PSM, 0)
///       3. DUSD.setBurnerStatus(USDC_PSM, false)
///       4. UsmRegistry.removeUsm(USDC_PSM)
///       5. AltoAdapter.revokeContract(USDC_PSM)
///
/// @dev PREREQUISITE (separate timelock tx, must be finalized BEFORE treasury batch):
///        DUSD.setMinterStatus(FRXUSD_PSM, true)
///        DUSD.setMinterCeiling(FRXUSD_PSM, <sufficient ceiling>)
///        DUSD.setBurnerStatus(FRXUSD_PSM, true)
///
/// @dev Run with: forge script script/DeprecatePermissionlessUsdcUsm.s.sol --fork-url ethereum -vvv
contract DeprecatePermissionlessUsdcUsmScript is Script {
    address constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

    /// @dev Permissionless USDC PSM being deprecated
    address constant USDC_PSM = 0x4026db9152cEb2e6D376de72Efb70eb8F407A0e4;

    /// @dev Permissionless frxUSD PSM replacing it
    address constant FRXUSD_PSM = 0x7b9468fB9f3146ec82ceB2Dd75e6a47F3EAd5f79;

    /// @dev Frax ERC-4626 custodian: deposit USDC (6 dec) → receive frxUSD (18 dec) 1:1 USD value
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant USM_REGISTRY = 0xAD5620e10C33918E2C6A2E8E53325bf98c548E5e;
    address constant ALTO_ADAPTER = 0x4F46bb6948190eDd091c3A4f47DC2946Ae627369;

    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        // ─────────────────────────────────────────────────────────────────────
        // PHASE 1: Treasury migration calldata
        // ─────────────────────────────────────────────────────────────────────

        uint256 usdcExposure = IUsm(USDC_PSM).getAvailableLiquidity();
        require(usdcExposure > 0, "USDC PSM is already empty");

        // DUSD required to buy all USDC from the USDC PSM (buy fee included)
        // Returns: (assetAmount, stableTokenSold, grossAmount, fee)
        (, uint256 dusdNeeded,,) = IUsm(USDC_PSM).getStableTokenAmountForBuyAsset(usdcExposure);

        // frxUSD to sell into the frxUSD PSM to receive at least dusdNeeded DUSD (rounds UP)
        // Returns: (assetAmount, stableTokenBought, grossAmount, fee)
        (uint256 frxUsdNeeded,,,) = IUsm(FRXUSD_PSM).getAssetAmountForSellAsset(dusdNeeded);

        // USDC to deposit: frxUSD (18 dec) → USDC (6 dec), rounded UP
        uint256 usdcToDeposit = (frxUsdNeeded + 1e12 - 1) / 1e12;

        console.log("=== Deprecate Permissionless USDC USM ===");
        console.log("");
        console.log("USDC PSM (to deprecate):", USDC_PSM);
        console.log("frxUSD PSM:             ", FRXUSD_PSM);
        console.log("Frax Custodian:         ", FRAX_CUSTODIAN);
        console.log("Treasury:               ", TREASURY);
        console.log("Timelock:               ", TIMELOCK);
        console.log("");
        console.log("--- Computed amounts ---");
        console.log("USDC exposure in PSM   (6  dec):", usdcExposure);
        console.log("DUSD needed to buy all (18 dec):", dusdNeeded);
        console.log("frxUSD needed for DUSD (18 dec):", frxUsdNeeded);
        console.log("USDC to deposit        (6  dec):", usdcToDeposit);
        console.log("");
        console.log("PREREQUISITE (separate timelock tx, must be finalized before treasury batch):");
        console.log("  DUSD.setMinterStatus(FRXUSD_PSM, true)");
        console.log("  DUSD.setMinterCeiling(FRXUSD_PSM, <sufficient ceiling>)");
        console.log("  DUSD.setBurnerStatus(FRXUSD_PSM, true)");
        console.log("");
        console.log("=== PHASE 1: TREASURY BATCH (execute after prerequisite is live) ===");
        console.log("Treasury must hold at least", usdcToDeposit, "USDC (6 dec) before execution.");
        console.log("");

        // Tx 1: Approve USDC → Frax Custodian
        {
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, usdcToDeposit);
            console.log("--- Tx 1: Approve USDC to Frax Custodian ---");
            console.log("To:    ", USDC);
            console.log("Value:  0");
            console.log("Data:");
            console.logBytes(data);
            console.log("");
        }

        // Tx 2: Deposit USDC → Frax Custodian (→ frxUSD 1:1)
        {
            bytes memory data = abi.encodeCall(IERC4626.deposit, (usdcToDeposit, TREASURY));
            console.log("--- Tx 2: Deposit USDC into Frax Custodian (receive frxUSD 1:1) ---");
            console.log("To:    ", FRAX_CUSTODIAN);
            console.log("Value:  0");
            console.log("Data:");
            console.logBytes(data);
            console.log("Expected frxUSD received (18 dec, approx):", usdcToDeposit * 1e12);
            console.log("");
        }

        // Tx 3: Approve frxUSD → frxUSD PSM
        {
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_PSM, frxUsdNeeded);
            console.log("--- Tx 3: Approve frxUSD to frxUSD PSM ---");
            console.log("To:    ", FRXUSD);
            console.log("Value:  0");
            console.log("Data:");
            console.logBytes(data);
            console.log("");
        }

        // Tx 4: Sell frxUSD → frxUSD PSM (→ DUSD)
        {
            // sellAsset(maxAmount, receiver): actual frxUSD pulled may be <= frxUsdNeeded;
            // DUSD received is guaranteed >= dusdNeeded
            bytes memory data = abi.encodeWithSelector(IUsm.sellAsset.selector, frxUsdNeeded, TREASURY);
            console.log("--- Tx 4: Sell frxUSD into frxUSD PSM to receive DUSD ---");
            console.log("To:    ", FRXUSD_PSM);
            console.log("Value:  0");
            console.log("Data:");
            console.logBytes(data);
            console.log("Guaranteed minimum DUSD received (18 dec):", dusdNeeded);
            console.log("");
        }

        // Tx 5: Approve DUSD → USDC PSM
        {
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, USDC_PSM, dusdNeeded);
            console.log("--- Tx 5: Approve DUSD to USDC PSM ---");
            console.log("To:    ", DUSD);
            console.log("Value:  0");
            console.log("Data:");
            console.logBytes(data);
            console.log("");
        }

        // Tx 6: Buy USDC ← USDC PSM (spend DUSD, receive USDC)
        {
            // buyAsset(minAmount, receiver): spend dusdNeeded DUSD, receive at least usdcExposure USDC
            bytes memory data = abi.encodeWithSelector(IUsm.buyAsset.selector, usdcExposure, TREASURY);
            console.log("--- Tx 6: Buy all USDC from USDC PSM using DUSD ---");
            console.log("To:    ", USDC_PSM);
            console.log("Value:  0");
            console.log("Data:");
            console.logBytes(data);
            console.log("DUSD spent         (18 dec):", dusdNeeded);
            console.log("Min USDC received  (6  dec):", usdcExposure);
            console.log("");
        }

        console.log("Expected outcome after Phase 1:");
        console.log("  USDC PSM getAvailableLiquidity() -> 0");
        console.log("  Treasury USDC deposited  (6 dec):", usdcToDeposit);
        console.log("  Treasury USDC received   (6 dec):", usdcExposure);

        // ─────────────────────────────────────────────────────────────────────
        // PHASE 2: Timelock cleanup — build scheduleBatch + executeBatch JSONs
        // ─────────────────────────────────────────────────────────────────────

        console.log("");
        console.log("=== PHASE 2: TIMELOCK CLEANUP (schedule after Phase 1 is complete) ===");

        uint256 batchSize = 5;
        address[] memory targets = new address[](batchSize);
        uint256[] memory values = new uint256[](batchSize);
        bytes[] memory payloads = new bytes[](batchSize);

        // 1. Revoke DUSD minting permission
        targets[0] = DUSD;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IDUSD.setMinterStatus, (USDC_PSM, false));

        // 2. Zero out DUSD minter ceiling
        targets[1] = DUSD;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterCeiling, (USDC_PSM, 0));

        // 3. Revoke DUSD burning permission
        targets[2] = DUSD;
        values[2] = 0;
        payloads[2] = abi.encodeCall(IDUSD.setBurnerStatus, (USDC_PSM, false));

        // 4. Remove from USM registry
        targets[3] = USM_REGISTRY;
        values[3] = 0;
        payloads[3] = abi.encodeCall(IUsmRegistry.removeUsm, (USDC_PSM));

        // 5. Revoke adapter approval
        targets[4] = ALTO_ADAPTER;
        values[4] = 0;
        payloads[4] = abi.encodeWithSignature("revokeContract(address)", USDC_PSM);

        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();
        console.log("Timelock min delay (s):", minDelay);
        console.log("");

        console.log("Batch calls:");
        console.log("  [0] DUSD.setMinterStatus(USDC_PSM, false)");
        console.log("  [1] DUSD.setMinterCeiling(USDC_PSM, 0)");
        console.log("  [2] DUSD.setBurnerStatus(USDC_PSM, false)");
        console.log("  [3] UsmRegistry.removeUsm(USDC_PSM)");
        console.log("  [4] AltoAdapter.revokeContract(USDC_PSM)");
        console.log("");

        _writeSafeTimelockBatchJson(
            "deprecate-permissionless-usdc-usm-cleanup", TIMELOCK, targets, values, payloads, minDelay
        );
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
        console.log("  1. safe-tx-%s-schedule.json  (propose to timelock)", name);
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
