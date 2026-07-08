// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

struct MarketCeilingUpdate {
    address market;
    uint256 borrowedAssets;
    uint256 newCeiling;
}

/// @title Schedule Update meth/reth Mint Ceilings
/// @notice Generates scheduleBatch and executeBatch Safe txs to align meth and reth market debt ceilings
///         and DUSD minter ceilings with current borrowed assets plus a 5% buffer
/// @dev Run with `forge script script/ScheduleUpdateMethRethMintCeilings.s.sol:ScheduleUpdateMethRethMintCeilingsScript --rpc-url ethereum -vvvv`
/// @dev Re-run before scheduling if borrows may have increased since the last script execution.
contract ScheduleUpdateMethRethMintCeilingsScript is Script {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;

    uint256 constant BUFFER_BPS = 500; // 5%

    string constant SAFE_BATCH_NAME = "update-meth-reth-mint-ceilings";
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

    /// @dev Returns meth and reth ceiling updates based on current on-chain borrowed assets.
    function computeUpdates() public view returns (MarketCeilingUpdate[] memory updates) {
        updates = new MarketCeilingUpdate[](2);
        updates[0] = _computeMarketUpdate(METH_MARKET);
        updates[1] = _computeMarketUpdate(RETH_MARKET);
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
}
