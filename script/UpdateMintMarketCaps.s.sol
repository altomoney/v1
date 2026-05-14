// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    IDcfDlbPriorityLiquidationEngine
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

/// @title Update Mint Market Caps
/// @notice Generates scheduleBatch and executeBatch Safe TX JSON files for updating
///         mint market debt ceilings and DUSD minter ceilings via the timelock.
/// @dev Run with: forge script script/UpdateMintMarketCaps.s.sol -vvv
contract UpdateMintMarketCapsScript is Script {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    // Below values are sourced from contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json

    // Mint markets
    address constant WETH_MARKET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address constant WETH_LIQUIDATION_ENGINE = 0x984E3D783E78ac5c5192CaEB562bE84306724A86;

    address constant WSTETH_MARKET = 0xfd8c25047f4397dC5461B919999585a2a3EaC2eF;
    address constant WSTETH_LIQUIDATION_ENGINE = 0xB9724552a774369E8319d8EDC00A7cb95fc5dDe2;

    address constant SUSDE_MINT_MARKET = 0x210bF54092B66443FddFec0f3F156e74B04CD2a2;
    address constant SUSDE_MINT_LIQUIDATION_ENGINE = 0xE81419819a776404d318864C3A462E5cdac783fA;

    address constant SYRUP_USDC_MINT_MARKET = 0xD2eA320713158a7b7eaE46025B8Ad4CBF3cdc87e;
    address constant SYRUP_USDC_MINT_LIQUIDATION_ENGINE = 0xa6c519d3EC7763EA21F77A83017618CD51c0d118;

    address constant TBTC_MARKET = 0xE17F10f8535336143d4F2FE304f3Dcf7B23671e1;
    address constant TBTC_LIQUIDATION_ENGINE = 0xBD284dD74479F3cBf4B59eE8479eCe2bB48f96a7;

    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant METH_LIQUIDATION_ENGINE = 0x61786D966f3FE8c4a83317af680Ea8B0eF70f4A9;

    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;
    address constant RETH_LIQUIDATION_ENGINE = 0x2a3fB51184183405c975Bd8b355d4Dc43209f45B;

    // New debt ceilings (18 decimals)
    uint256 constant WETH_NEW_CAP = 60_000 * 1e18;
    uint256 constant WSTETH_NEW_CAP = 60_000 * 1e18;
    uint256 constant SUSDE_NEW_CAP = 35_000 * 1e18;
    uint256 constant SYRUP_USDC_NEW_CAP = 35_000 * 1e18;
    uint256 constant TBTC_NEW_CAP = 20_000 * 1e18;
    uint256 constant METH_NEW_CAP = 20_000 * 1e18;
    uint256 constant RETH_NEW_CAP = 20_000 * 1e18;

    uint256 constant MINTER_CEILING_BUFFER = 1.05 ether; // 1.05 * 1e18

    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));

        uint256 numMarkets = 7;

        address[] memory markets = new address[](numMarkets);
        address[] memory liquidationEngines = new address[](numMarkets);
        uint256[] memory newCaps = new uint256[](numMarkets);
        string[] memory marketNames = new string[](numMarkets);

        markets[0] = WETH_MARKET;
        liquidationEngines[0] = WETH_LIQUIDATION_ENGINE;
        newCaps[0] = WETH_NEW_CAP;
        marketNames[0] = "wETH";

        markets[1] = WSTETH_MARKET;
        liquidationEngines[1] = WSTETH_LIQUIDATION_ENGINE;
        newCaps[1] = WSTETH_NEW_CAP;
        marketNames[1] = "wstETH";

        markets[2] = SUSDE_MINT_MARKET;
        liquidationEngines[2] = SUSDE_MINT_LIQUIDATION_ENGINE;
        newCaps[2] = SUSDE_NEW_CAP;
        marketNames[2] = "sUSDe";

        markets[3] = SYRUP_USDC_MINT_MARKET;
        liquidationEngines[3] = SYRUP_USDC_MINT_LIQUIDATION_ENGINE;
        newCaps[3] = SYRUP_USDC_NEW_CAP;
        marketNames[3] = "syrupUSDC";

        markets[4] = TBTC_MARKET;
        liquidationEngines[4] = TBTC_LIQUIDATION_ENGINE;
        newCaps[4] = TBTC_NEW_CAP;
        marketNames[4] = "tBTC";

        markets[5] = METH_MARKET;
        liquidationEngines[5] = METH_LIQUIDATION_ENGINE;
        newCaps[5] = METH_NEW_CAP;
        marketNames[5] = "mETH";

        markets[6] = RETH_MARKET;
        liquidationEngines[6] = RETH_LIQUIDATION_ENGINE;
        newCaps[6] = RETH_NEW_CAP;
        marketNames[6] = "rETH";

        uint256[] memory minterCeilings = new uint256[](numMarkets);
        uint256[] memory maxLiquidationLtvs = new uint256[](numMarkets);

        console.log("=== Update Mint Market Caps ===");
        console.log("Timelock:  ", TIMELOCK);
        console.log("DUSD:      ", DUSD);
        console.log("");
        console.log("Market caps and computed minter ceilings:");
        console.log("------------------------------------------------------------");

        for (uint256 i = 0; i < numMarkets; i++) {
            uint256 maxLiquidationLtv =
                IDcfDlbPriorityLiquidationEngine(liquidationEngines[i]).liquidationConfiguration().maxLiquidationLtv;
            uint256 minterCeiling = newCaps[i] * MINTER_CEILING_BUFFER / maxLiquidationLtv;

            maxLiquidationLtvs[i] = maxLiquidationLtv;
            minterCeilings[i] = minterCeiling;

            console.log(string.concat("  [", marketNames[i], "]"));
            console.log("    Market:             ", markets[i]);
            console.log("    LiquidationEngine:  ", liquidationEngines[i]);
            console.log("    maxLiquidationLtv:  ", maxLiquidationLtv);
            console.log("    New debt ceiling:   ", newCaps[i]);
            console.log("    Minter ceiling:     ", minterCeiling);
        }

        console.log("------------------------------------------------------------");

        // Build batch: 7x setDebtCeiling + 7x setMinterCeiling = 14 calls
        uint256 batchSize = numMarkets * 2;
        address[] memory targets = new address[](batchSize);
        uint256[] memory values = new uint256[](batchSize);
        bytes[] memory payloads = new bytes[](batchSize);

        for (uint256 i = 0; i < numMarkets; i++) {
            // setDebtCeiling on the market
            targets[i] = markets[i];
            values[i] = 0;
            payloads[i] = abi.encodeCall(AltoMintMarket.setDebtCeiling, (newCaps[i]));

            // setMinterCeiling on DUSD for the market
            uint256 j = numMarkets + i;
            targets[j] = DUSD;
            values[j] = 0;
            payloads[j] = abi.encodeCall(IDUSD.setMinterCeiling, (markets[i], minterCeilings[i]));
        }

        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();
        console.log("\nTimelock min delay (s): ", minDelay);

        _writeSafeTimelockBatchJson("update-mint-market-caps", TIMELOCK, targets, values, payloads, minDelay);
        _writeOutputJson(marketNames, markets, liquidationEngines, newCaps, maxLiquidationLtvs, minterCeilings);

        console.log("\nDone.");
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

        console.log("\nSafe TX Builder JSONs written:");
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

    function _writeOutputJson(
        string[] memory marketNames,
        address[] memory markets,
        address[] memory liquidationEngines,
        uint256[] memory newCaps,
        uint256[] memory maxLiquidationLtvs,
        uint256[] memory minterCeilings
    ) internal {
        string memory updatesJson = "";

        for (uint256 i = 0; i < markets.length; i++) {
            string memory key = marketNames[i];
            string memory entryJson = "";
            entryJson = vm.serializeAddress(key, "market", markets[i]);
            entryJson = vm.serializeAddress(key, "liquidationEngine", liquidationEngines[i]);
            entryJson = vm.serializeUint(key, "newDebtCeiling", newCaps[i]);
            entryJson = vm.serializeUint(key, "maxLiquidationLtv", maxLiquidationLtvs[i]);
            entryJson = vm.serializeUint(key, "minterCeiling", minterCeilings[i]);
            updatesJson = vm.serializeString("updates", key, entryJson);
        }

        string memory metaJson = "";
        metaJson = vm.serializeAddress("meta", "timelock", TIMELOCK);
        metaJson = vm.serializeAddress("meta", "dusd", DUSD);
        metaJson = vm.serializeString("meta", "updates", updatesJson);

        string memory outputPath = string.concat(OUTPUT_DIR, "/update-mint-market-caps-output.json");
        vm.writeJson(metaJson, outputPath);
        console.log("\nOutput summary written to:", outputPath);
    }
}
