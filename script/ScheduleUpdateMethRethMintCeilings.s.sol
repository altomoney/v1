// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {MarketConfig} from "@alto/lending/libraries/PendingLib.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

struct MarketCeilingUpdate {
    address market;
    uint256 borrowedAssets;
    uint256 newCeiling;
}

struct VaultCapUpdate {
    address market;
    uint256 currentCap;
    uint256 newCap;
}

struct TreasurySafeTx {
    address to;
    bytes data;
}

/// @title Schedule Update meth/reth Mint Ceilings and DUSD Vault Caps
/// @notice Generates:
///         1) Timelock scheduleBatch / executeBatch Safe txs to align meth and reth market debt ceilings
///            and DUSD minter ceilings with current borrowed assets plus a 5% buffer
///         2) Direct Safe txs (timelock admin / vault curator) to submitCap 40k DUSD on each AltoDUSDVault market
/// @dev Run with `forge script script/ScheduleUpdateMethRethMintCeilings.s.sol:ScheduleUpdateMethRethMintCeilingsScript --rpc-url ethereum -vvvv`
/// @dev Re-run before scheduling if borrows may have increased since the last script execution.
contract ScheduleUpdateMethRethMintCeilingsScript is Script {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant DUSD_VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;
    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;

    address constant SYRUP_USDC_BORROW_MARKET = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant SUSDE_BORROW_MARKET = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address constant PAXG_BORROW_MARKET = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817;
    address constant WBTC_BORROW_MARKET = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
    address constant CBBTC_BORROW_MARKET = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;

    uint256 constant BUFFER_BPS = 500; // 5%
    uint256 constant NEW_VAULT_SUPPLY_CAP = 40_000 ether;
    uint256 constant EXPECTED_CURRENT_VAULT_SUPPLY_CAP = 80_000 ether;

    string constant SAFE_BATCH_NAME = "update-meth-reth-mint-ceilings";
    string constant VAULT_CAP_SAFE_BATCH_NAME = "update-dusd-vault-supply-caps";
    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        MarketCeilingUpdate[] memory updates = computeUpdates();
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = buildBatch(updates);
        uint256 delay = TimelockController(payable(TIMELOCK)).getMinDelay();

        bytes memory scheduleBatchData = abi.encodeCall(
            TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), bytes32(0), delay)
        );
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), bytes32(0)));

        VaultCapUpdate[] memory vaultCapUpdates = computeVaultCapUpdates();
        TreasurySafeTx[] memory vaultCapTxs = getVaultCapSafeTransactions(vaultCapUpdates);

        console.log("=== Update meth/reth Mint Ceilings ===");
        console.log("Timelock:", TIMELOCK);
        console.log("DUSD:", DUSD);
        console.log("meth market:", METH_MARKET);
        console.log("reth market:", RETH_MARKET);
        console.log("Timelock delay (seconds):", delay);

        for (uint256 i = 0; i < updates.length; ++i) {
            console.log("\nMarket:", updates[i].market);
            console.log("  borrowed assets:", updates[i].borrowedAssets);
            console.log("  new ceiling (+5%%):", updates[i].newCeiling);
        }

        console.log("\n=== Update AltoDUSDVault Supply Caps ===");
        console.log("Timelock admin / vault curator (Safe):", TIMELOCK_ADMIN);
        console.log("DUSD Vault:", DUSD_VAULT);
        console.log("New supply cap per market:", NEW_VAULT_SUPPLY_CAP);
        console.log("Vault submitCap tx count:", vaultCapTxs.length);

        for (uint256 i = 0; i < vaultCapUpdates.length; ++i) {
            console.log("\nVault market:", vaultCapUpdates[i].market);
            console.log("  current cap:", vaultCapUpdates[i].currentCap);
            console.log("  new cap:", vaultCapUpdates[i].newCap);
        }

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", SAFE_BATCH_NAME, "-schedule.json"),
            _buildSafeJson(string.concat(SAFE_BATCH_NAME, " - Schedule"), TIMELOCK, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", SAFE_BATCH_NAME, "-execute.json"),
            _buildSafeJson(string.concat(SAFE_BATCH_NAME, " - Execute"), TIMELOCK, executeBatchData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", VAULT_CAP_SAFE_BATCH_NAME, ".json"),
            _buildSafeBatchJson(VAULT_CAP_SAFE_BATCH_NAME, vaultCapTxs)
        );

        console.log("\nSafe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json", SAFE_BATCH_NAME);
        console.log("  2. safe-tx-%s-execute.json", SAFE_BATCH_NAME);
        console.log("  3. safe-tx-%s.json (submit from timelock admin Safe)", VAULT_CAP_SAFE_BATCH_NAME);
    }

    /// @dev Returns meth and reth ceiling updates based on current on-chain borrowed assets.
    function computeUpdates() public view returns (MarketCeilingUpdate[] memory updates) {
        updates = new MarketCeilingUpdate[](2);
        updates[0] = _computeMarketUpdate(METH_MARKET);
        updates[1] = _computeMarketUpdate(RETH_MARKET);
    }

    /// @dev Returns vault supply-cap updates for each AltoDUSDVault market (80k -> 40k).
    function computeVaultCapUpdates() public view returns (VaultCapUpdate[] memory updates) {
        address[] memory markets = _vaultMarkets();
        updates = new VaultCapUpdate[](markets.length);

        for (uint256 i = 0; i < markets.length; ++i) {
            MarketConfig memory config = IAltoVault(DUSD_VAULT).config(markets[i]);
            uint256 currentCap = uint256(config.cap);
            require(currentCap == EXPECTED_CURRENT_VAULT_SUPPLY_CAP, "unexpected current vault supply cap");
            require(NEW_VAULT_SUPPLY_CAP < currentCap, "new vault cap must be lower");

            updates[i] =
                VaultCapUpdate({market: markets[i], currentCap: currentCap, newCap: NEW_VAULT_SUPPLY_CAP});
        }
    }

    /// @dev Builds direct Safe txs for the vault curator (timelock admin) to call submitCap.
    function getVaultCapSafeTransactions(VaultCapUpdate[] memory updates)
        public
        pure
        returns (TreasurySafeTx[] memory txs)
    {
        txs = new TreasurySafeTx[](updates.length);
        for (uint256 i = 0; i < updates.length; ++i) {
            txs[i] = TreasurySafeTx({
                to: DUSD_VAULT,
                data: abi.encodeCall(IAltoVaultBase.submitCap, (updates[i].market, updates[i].newCap))
            });
        }
    }

    /// @dev Builds the timelock batch: setDebtCeiling on each market, then setMinterCeiling on DUSD.
    function buildBatch(MarketCeilingUpdate[] memory updates)
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](updates.length * 2);
        values = new uint256[](updates.length * 2);
        payloads = new bytes[](updates.length * 2);

        for (uint256 i = 0; i < updates.length; ++i) {
            uint256 baseIndex = i * 2;

            targets[baseIndex] = updates[i].market;
            values[baseIndex] = 0;
            payloads[baseIndex] = abi.encodeCall(AltoMintMarket.setDebtCeiling, (updates[i].newCeiling));

            targets[baseIndex + 1] = DUSD;
            values[baseIndex + 1] = 0;
            payloads[baseIndex + 1] =
                abi.encodeCall(IDUSD.setMinterCeiling, (updates[i].market, updates[i].newCeiling));
        }
    }

    function _vaultMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](5);
        markets[0] = SYRUP_USDC_BORROW_MARKET;
        markets[1] = SUSDE_BORROW_MARKET;
        markets[2] = PAXG_BORROW_MARKET;
        markets[3] = WBTC_BORROW_MARKET;
        markets[4] = CBBTC_BORROW_MARKET;
    }

    function _computeMarketUpdate(address market) internal view returns (MarketCeilingUpdate memory update) {
        update.market = market;
        update.borrowedAssets = IMarket(market).totalBorrowed().assets;
        update.newCeiling = update.borrowedAssets + (update.borrowedAssets * BUFFER_BPS / 10_000);
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

    function _buildSafeBatchJson(string memory name, TreasurySafeTx[] memory txs)
        internal
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '","txBuilderVersion":"1.16.5"},"transactions":['
        );

        for (uint256 i = 0; i < txs.length; ++i) {
            if (i > 0) {
                json = string.concat(json, ",");
            }
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(txs[i].to),
                '","value":"0","data":"',
                vm.toString(txs[i].data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        return string.concat(json, "]}");
    }
}
