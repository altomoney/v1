// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @dev Minimal view/mutating surface of AltoMintMarket needed by this script.
interface IAltoMintMarketLike {
    function setDebtCeiling(uint256 _debtCeiling) external;
    function totalSupply() external view returns (uint128 assets, uint128 shares);
    function liquidationEngine() external view returns (address);
}

/// @dev Minimal surface of the liquidation engine needed to read maxLiquidationLtv.
interface ILiquidationEngineLike {
    function minLltv() external view returns (uint256);
}

/// @title Update sUSDe / syrupUSDC Mint Market Debt Ceilings
/// @notice Generates Safe Transaction Builder JSON files for the timelock `scheduleBatch` and
///         `executeBatch` calls that:
///           1. Set the debt ceiling (`totalSupply.assets`) on the sUSDe mint market.
///           2. Set the debt ceiling (`totalSupply.assets`) on the syrupUSDC mint market.
///           3. Update the DUSD minter ceiling for the sUSDe mint market.
///           4. Update the DUSD minter ceiling for the syrupUSDC mint market.
/// @dev Owner of the mint markets and DUSD is the TimelockController, so all four actions are
///      wrapped in a single timelock batch. Run against a mainnet RPC to read live values:
///        forge script script/UpdateMintMarketDebtCeilings.s.sol --rpc-url $MAINNET_RPC_URL
contract UpdateMintMarketDebtCeilingsScript is Script {
    // --- Deployed contract addresses (ethereum-mainnet) ---
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant SUSDE_MINT_MARKET = 0x210bF54092B66443FddFec0f3F156e74B04CD2a2;
    address constant SYRUP_USDC_MINT_MARKET = 0xD2eA320713158a7b7eaE46025B8Ad4CBF3cdc87e;

    // --- Target debt ceilings (new totalSupply.assets), DUSD has 18 decimals ---
    uint256 constant SUSDE_NEW_DEBT_CEILING = 35_000 ether;
    uint256 constant SYRUP_USDC_NEW_DEBT_CEILING = 54_000 ether;

    // Minter ceiling multiplier used at deploy time: debtCeiling * 1.05e18 / maxLiquidationLtv.
    uint256 constant MINTER_CEILING_MULTIPLIER = 1.05 ether;

    string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string constant BATCH_NAME = "mint-market-debt-ceiling-update";

    function run() public {
        // --- Read current on-chain values ---
        (uint128 susdeOldCeiling,) = IAltoMintMarketLike(SUSDE_MINT_MARKET).totalSupply();
        (uint128 syrupOldCeiling,) = IAltoMintMarketLike(SYRUP_USDC_MINT_MARKET).totalSupply();

        (, uint256 susdeOldMinterCeiling) = IDUSD(DUSD).minterConfig(SUSDE_MINT_MARKET);
        (, uint256 syrupOldMinterCeiling) = IDUSD(DUSD).minterConfig(SYRUP_USDC_MINT_MARKET);

        uint256 susdeMaxLltv = ILiquidationEngineLike(
            IAltoMintMarketLike(SUSDE_MINT_MARKET).liquidationEngine()
        ).minLltv();
        uint256 syrupMaxLltv = ILiquidationEngineLike(
            IAltoMintMarketLike(SYRUP_USDC_MINT_MARKET).liquidationEngine()
        ).minLltv();

        // --- Compute new minter ceilings (deploy formula) ---
        uint256 susdeNewMinterCeiling = SUSDE_NEW_DEBT_CEILING * MINTER_CEILING_MULTIPLIER / susdeMaxLltv;
        uint256 syrupNewMinterCeiling = SYRUP_USDC_NEW_DEBT_CEILING * MINTER_CEILING_MULTIPLIER / syrupMaxLltv;

        _logChange(
            "sUSDe mint market",
            SUSDE_MINT_MARKET,
            susdeOldCeiling,
            SUSDE_NEW_DEBT_CEILING,
            susdeOldMinterCeiling,
            susdeNewMinterCeiling,
            susdeMaxLltv
        );
        _logChange(
            "syrupUSDC mint market",
            SYRUP_USDC_MINT_MARKET,
            syrupOldCeiling,
            SYRUP_USDC_NEW_DEBT_CEILING,
            syrupOldMinterCeiling,
            syrupNewMinterCeiling,
            syrupMaxLltv
        );

        // --- Build the timelock batch ---
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);

        targets[0] = SUSDE_MINT_MARKET;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IAltoMintMarketLike.setDebtCeiling, (SUSDE_NEW_DEBT_CEILING));

        targets[1] = SYRUP_USDC_MINT_MARKET;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IAltoMintMarketLike.setDebtCeiling, (SYRUP_USDC_NEW_DEBT_CEILING));

        targets[2] = DUSD;
        values[2] = 0;
        payloads[2] = abi.encodeCall(IDUSD.setMinterCeiling, (SUSDE_MINT_MARKET, susdeNewMinterCeiling));

        targets[3] = DUSD;
        values[3] = 0;
        payloads[3] = abi.encodeCall(IDUSD.setMinterCeiling, (SYRUP_USDC_MINT_MARKET, syrupNewMinterCeiling));

        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();

        _writeSafeTimelockBatchJson(BATCH_NAME, TIMELOCK, targets, values, payloads, minDelay);
    }

    function _logChange(
        string memory label,
        address market,
        uint256 oldCeiling,
        uint256 newCeiling,
        uint256 oldMinterCeiling,
        uint256 newMinterCeiling,
        uint256 maxLltv
    ) internal pure {
        console.log("=================================================");
        console.log(label, market);
        console.log("  maxLiquidationLtv (1e18):", maxLltv);
        console.log("  debtCeiling  OLD (wei):", oldCeiling);
        console.log("  debtCeiling  OLD (DUSD):", oldCeiling / 1 ether);
        console.log("  debtCeiling  NEW (wei):", newCeiling);
        console.log("  debtCeiling  NEW (DUSD):", newCeiling / 1 ether);
        console.log("  minterCeiling OLD (wei):", oldMinterCeiling);
        console.log("  minterCeiling OLD (DUSD):", oldMinterCeiling / 1 ether);
        console.log("  minterCeiling NEW (wei):", newMinterCeiling);
        console.log("  minterCeiling NEW (DUSD):", newMinterCeiling / 1 ether);
    }

    /// @dev Writes Safe Transaction Builder JSON files for a timelock batch transaction.
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

        console.log("=================================================");
        console.log("Timelock delay (seconds):", delay);
        console.log("Safe TX Builder JSONs written:");
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
}
