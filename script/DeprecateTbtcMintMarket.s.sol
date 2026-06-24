// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";

/// @title Deprecate tBTC Mint Market
/// @notice Generates Safe wallet calldata to lower tBTC mint market debt ceiling to 4,000 DUSD,
///         reallocate 16,000 DUSD capacity (+8,000 each) to sUSDe and syrupUSDC mint markets,
///         and update DUSD minter ceilings using `debtCeiling * 1.05 / maxLiquidationLtv`.
///
///         Flow (2 transactions via Safe):
///           1. timelock.scheduleBatch — queue market + DUSD updates
///           2. timelock.executeBatch  — execute after min delay elapses
///
///         forge script script/DeprecateTbtcMintMarket.s.sol:DeprecateTbtcMintMarketScript --fork-url $ETH_RPC_URL
contract DeprecateTbtcMintMarketScript is Script {
    string private constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string private constant SAFE_TX_NAME = "deprecate-tbtc-mint-market";

    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address public constant TBTC_MARKET = 0xE17F10f8535336143d4F2FE304f3Dcf7B23671e1;
    address public constant SUSDE_MINT_MARKET = 0x210bF54092B66443FddFec0f3F156e74B04CD2a2;
    address public constant SYRUPUSDC_MINT_MARKET = 0xD2eA320713158a7b7eaE46025B8Ad4CBF3cdc87e;

    uint256 public constant EXPECTED_TBTC_DEBT_CEILING = 20_000 ether;
    uint256 public constant NEW_TBTC_DEBT_CEILING = 4_000 ether;
    uint256 public constant REALLOCATION_PER_MARKET = 8_000 ether;
    uint256 public constant MINTER_CEILING_NUMERATOR = 1.05 ether;

    function run() public {
        uint256 currentTbtcDebtCeiling = IMarket(TBTC_MARKET).totalSupply().assets;
        uint256 currentSusdeDebtCeiling = IMarket(SUSDE_MINT_MARKET).totalSupply().assets;
        uint256 currentSyrupDebtCeiling = IMarket(SYRUPUSDC_MINT_MARKET).totalSupply().assets;

        require(currentTbtcDebtCeiling == EXPECTED_TBTC_DEBT_CEILING, "unexpected tBTC debt ceiling");

        uint256 freedCapacity = currentTbtcDebtCeiling - NEW_TBTC_DEBT_CEILING;
        require(freedCapacity == REALLOCATION_PER_MARKET * 2, "freed capacity mismatch");

        uint256 newSusdeDebtCeiling = currentSusdeDebtCeiling + REALLOCATION_PER_MARKET;
        uint256 newSyrupDebtCeiling = currentSyrupDebtCeiling + REALLOCATION_PER_MARKET;

        uint256 tbtcMaxLiquidationLtv = _maxLiquidationLtv(TBTC_MARKET);
        uint256 susdeMaxLiquidationLtv = _maxLiquidationLtv(SUSDE_MINT_MARKET);
        uint256 syrupMaxLiquidationLtv = _maxLiquidationLtv(SYRUPUSDC_MINT_MARKET);

        uint256 newTbtcMinterCeiling = _minterCeiling(NEW_TBTC_DEBT_CEILING, tbtcMaxLiquidationLtv);
        uint256 newSusdeMinterCeiling = _minterCeiling(newSusdeDebtCeiling, susdeMaxLiquidationLtv);
        uint256 newSyrupMinterCeiling = _minterCeiling(newSyrupDebtCeiling, syrupMaxLiquidationLtv);

        (, uint256 currentSusdeMinterCeiling) = IDUSD(DUSD).minterConfig(SUSDE_MINT_MARKET);
        (, uint256 currentSyrupMinterCeiling) = IDUSD(DUSD).minterConfig(SYRUPUSDC_MINT_MARKET);

        _logSummary(
            currentTbtcDebtCeiling,
            newSusdeDebtCeiling,
            newSyrupDebtCeiling,
            newTbtcMinterCeiling,
            currentSusdeMinterCeiling,
            newSusdeMinterCeiling,
            currentSyrupMinterCeiling,
            newSyrupMinterCeiling
        );

        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildBatch(
            newSusdeDebtCeiling, newSyrupDebtCeiling, newTbtcMinterCeiling, newSusdeMinterCeiling, newSyrupMinterCeiling
        );
        _logBatch(targets, values, payloads, minDelay);
        _writeTimelockJson(SAFE_TX_NAME, targets, values, payloads, minDelay);
    }

    function _logSummary(
        uint256 currentTbtcDebtCeiling,
        uint256 newSusdeDebtCeiling,
        uint256 newSyrupDebtCeiling,
        uint256 newTbtcMinterCeiling,
        uint256 currentSusdeMinterCeiling,
        uint256 newSusdeMinterCeiling,
        uint256 currentSyrupMinterCeiling,
        uint256 newSyrupMinterCeiling
    ) internal view {
        uint256 freedCapacity = currentTbtcDebtCeiling - NEW_TBTC_DEBT_CEILING;

        console.log("=== Deprecate tBTC Mint Market ===");
        console.log("DUSD:", DUSD);
        console.log("Timelock:", TIMELOCK);
        console.log("tBTC mint market:", TBTC_MARKET);
        console.log("sUSDe mint market:", SUSDE_MINT_MARKET);
        console.log("syrupUSDC mint market:", SYRUPUSDC_MINT_MARKET);
        console.log("Current tBTC debt ceiling:", currentTbtcDebtCeiling);
        console.log("New tBTC debt ceiling:", NEW_TBTC_DEBT_CEILING);
        console.log("Freed capacity:", freedCapacity);
        console.log("New sUSDe debt ceiling:", newSusdeDebtCeiling);
        console.log("New syrupUSDC debt ceiling:", newSyrupDebtCeiling);
        console.log("New tBTC DUSD minter ceiling:", newTbtcMinterCeiling);
        console.log("sUSDe current DUSD minter ceiling:", currentSusdeMinterCeiling);
        console.log("sUSDe new expected DUSD minter ceiling:", newSusdeMinterCeiling);
        console.log("syrupUSDC current DUSD minter ceiling:", currentSyrupMinterCeiling);
        console.log("syrupUSDC new expected DUSD minter ceiling:", newSyrupMinterCeiling);
        console.log("Timelock min delay (seconds):", TimelockController(payable(TIMELOCK)).getMinDelay());
        console.log("");
    }

    function _buildBatch(
        uint256 newSusdeDebtCeiling,
        uint256 newSyrupDebtCeiling,
        uint256 newTbtcMinterCeiling,
        uint256 newSusdeMinterCeiling,
        uint256 newSyrupMinterCeiling
    ) internal pure returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads) {
        targets = new address[](6);
        values = new uint256[](6);
        payloads = new bytes[](6);

        targets[0] = TBTC_MARKET;
        values[0] = 0;
        payloads[0] = abi.encodeCall(AltoMintMarket.setDebtCeiling, (NEW_TBTC_DEBT_CEILING));

        targets[1] = DUSD;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterCeiling, (TBTC_MARKET, newTbtcMinterCeiling));

        targets[2] = SUSDE_MINT_MARKET;
        values[2] = 0;
        payloads[2] = abi.encodeCall(AltoMintMarket.setDebtCeiling, (newSusdeDebtCeiling));

        targets[3] = DUSD;
        values[3] = 0;
        payloads[3] = abi.encodeCall(IDUSD.setMinterCeiling, (SUSDE_MINT_MARKET, newSusdeMinterCeiling));

        targets[4] = SYRUPUSDC_MINT_MARKET;
        values[4] = 0;
        payloads[4] = abi.encodeCall(AltoMintMarket.setDebtCeiling, (newSyrupDebtCeiling));

        targets[5] = DUSD;
        values[5] = 0;
        payloads[5] = abi.encodeCall(IDUSD.setMinterCeiling, (SYRUPUSDC_MINT_MARKET, newSyrupMinterCeiling));
    }

    function _maxLiquidationLtv(address market) internal view returns (uint256) {
        return IAltoLiquidationEngine(IMarket(market).liquidationEngine()).minLltv();
    }

    function _minterCeiling(uint256 debtCeiling, uint256 maxLiquidationLtv) internal pure returns (uint256) {
        return debtCeiling * MINTER_CEILING_NUMERATOR / maxLiquidationLtv;
    }

    function _logBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal pure {
        console.log("--- Timelock batch ---");
        for (uint256 i = 0; i < targets.length; i++) {
            console.log(string.concat("Tx ", vm.toString(i + 1), " | ", _txLabel(i + 1)));
            console.log("Target:", targets[i]);
            console.log("Value:", values[i]);
            console.logBytes(payloads[i]);
        }
        console.log("Delay (seconds):", delay);
        console.log("");
    }

    function _txLabel(uint256 txNum) internal pure returns (string memory) {
        if (txNum == 1) return "tBTC.setDebtCeiling(4000 DUSD)";
        if (txNum == 2) return "DUSD.setMinterCeiling(tBTC market)";
        if (txNum == 3) return "sUSDe.setDebtCeiling(+8000 DUSD)";
        if (txNum == 4) return "DUSD.setMinterCeiling(sUSDe market)";
        if (txNum == 5) return "syrupUSDC.setDebtCeiling(+8000 DUSD)";
        if (txNum == 6) return "DUSD.setMinterCeiling(syrupUSDC market)";
        return "unknown";
    }

    function _writeTimelockJson(
        string memory name,
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

        string memory scheduleFile = string.concat(OUTPUT_DIR, "/safe-tx-", name, "-schedule.json");
        string memory executeFile = string.concat(OUTPUT_DIR, "/safe-tx-", name, "-execute.json");

        vm.writeFile(scheduleFile, _buildSafeJson(string.concat(name, " - Schedule"), TIMELOCK, scheduleBatchData));
        vm.writeFile(executeFile, _buildSafeJson(string.concat(name, " - Execute"), TIMELOCK, executeBatchData));

        console.log("Safe TX Builder JSONs written:");
        console.log("  1.", scheduleFile);
        console.log("  2.", executeFile);
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
