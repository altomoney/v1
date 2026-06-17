// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarket, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

/// @title Increase SyrupUSDC Mint Market Debt Ceiling
/// @notice Generates timelock scheduleBatch / executeBatch Safe transactions to increase
///         SyrupUSDCMintMarket debt ceiling by 19,000 DUSD and update the DUSD minter ceiling.
///         forge script script/IncreaseSyrupUsdcMintMarketDebtCeiling.s.sol:IncreaseSyrupUsdcMintMarketDebtCeiling --rpc-url ethereum
contract IncreaseSyrupUsdcMintMarketDebtCeiling is Script {
    address internal constant SYRUP_USDC_MINT_MARKET = 0xD2eA320713158a7b7eaE46025B8Ad4CBF3cdc87e;
    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

    uint256 internal constant DEBT_CEILING_INCREASE = 19_000 ether;

    string internal constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string internal constant BATCH_NAME = "syrupusdc-mint-market-debt-ceiling-increase";

    function run() public {
        Balance memory supply = IMarket(SYRUP_USDC_MINT_MARKET).totalSupply();
        uint256 currentDebtCeiling = supply.assets;
        uint256 newDebtCeiling = currentDebtCeiling + DEBT_CEILING_INCREASE;

        address liquidationEngine = IMarket(SYRUP_USDC_MINT_MARKET).liquidationEngine();
        uint256 maxLiquidationLtv = IAltoLiquidationEngine(liquidationEngine).minLltv();
        uint256 newMinterCeiling = newDebtCeiling * 1.05 ether / maxLiquidationLtv;

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        uint256 minDelay = timelock.getMinDelay();

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);

        targets[0] = SYRUP_USDC_MINT_MARKET;
        values[0] = 0;
        payloads[0] = abi.encodeCall(AltoMintMarket.setDebtCeiling, (newDebtCeiling));

        targets[1] = DUSD;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterCeiling, (SYRUP_USDC_MINT_MARKET, newMinterCeiling));

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, minDelay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", BATCH_NAME, "-schedule.json"),
            _buildSafeJson(string.concat(BATCH_NAME, " - Schedule"), TIMELOCK, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", BATCH_NAME, "-execute.json"),
            _buildSafeJson(string.concat(BATCH_NAME, " - Execute"), TIMELOCK, executeBatchData)
        );

        console.log("=== SyrupUSDC Mint Market Debt Ceiling Increase ===");
        console.log("SyrupUSDC Mint Market:", SYRUP_USDC_MINT_MARKET);
        console.log("DUSD:", DUSD);
        console.log("Timelock:", TIMELOCK);
        console.log("Current debt ceiling:", currentDebtCeiling);
        console.log("Debt ceiling increase:", DEBT_CEILING_INCREASE);
        console.log("New debt ceiling:", newDebtCeiling);
        console.log("Max liquidation LTV:", maxLiquidationLtv);
        console.log("New minter ceiling:", newMinterCeiling);
        console.log("Timelock delay:", minDelay);
        console.log("");
        console.log("Safe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json  (propose)", BATCH_NAME);
        console.log("  2. safe-tx-%s-execute.json   (execute after delay)", BATCH_NAME);
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
