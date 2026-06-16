// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {DusdPoolMigrationHelper} from "script/helper/DusdPoolMigrationHelper.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title Deprecate USDC USM & Execute DUSD Pool Migration
/// @notice Generates Safe wallet calldata for:
///         1. Deprecating the USDC permissioned USM (drain liquidity to 0 via treasury)
///         2. Calling `executeMigration` on a deployed `DusdPoolMigrationHelper`
///
///         Run from treasury Safe multisig. Treasury holds USDC (not DUSD). DUSD for the USDC
///         USM buy is sourced via frxUSD USM: USDC → frxUSD (custodian) → DUSD (frxUSD USM)
///         → USDC (USDC USM drain). Net USDC balance is unchanged at ~1:1.
///
///         Prerequisites before Tx 9 (`executeMigration`):
///         - Deploy `DusdPoolMigrationHelper` with treasury as owner; set `migrationHelper` below.
///         Flow (11 transactions):
///           1-4   source DUSD from frxUSD USM (USDC → frxUSD → DUSD)
///           5-6   drain USDC permissioned USM with sourced DUSD
///           7-8   approve narrow/wide Uniswap position NFTs to migration helper
///           9     `DusdPoolMigrationHelper.executeMigration`
///           10-11 revoke NFT approvals from migration helper
///         forge script script/DeprecateUsdcUsmAndExecuteMigration.s.sol:DeprecateUsdcUsmAndExecuteMigrationScript --fork-url $ETH_RPC_URL

contract DeprecateUsdcUsmAndExecuteMigrationScript is Script {
    uint256 private constant USDC_TO_FRXUSD_SCALE = 1e12;
    uint256 private constant TX_COUNT = 11;
    string private constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string private constant SAFE_TX_NAME = "deprecate-usdc-usm-execute-migration-of-uniswap-pool";

    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address public constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
    address public constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address public constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;
    address public constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    uint256 public constant NARROW_POSITION_TOKEN_ID = 1150307;
    uint256 public constant WIDE_POSITION_TOKEN_ID = 1150308;

    // ─── Placeholder: set deployed helper address before generating Tx 7-9 ─────
    address public migrationHelper = 0x68D83e51a0883201B1bA19ed7ab06580f06Da2f8;

    // ─── Placeholder: slippage floors for `decreaseLiquidity` on old positions ─
    // @dev Set these slippage floors close to 1% below current onchain values.
    uint256 public minExpectedDusdFromNarrowPosition = 291_500 ether;
    uint256 public minExpectedUsdcFromNarrowPosition = 482_300 * 1e6;
    uint256 public minExpectedDusdFromWidePosition = 36_600 ether;
    uint256 public minExpectedUsdcFromWidePosition = 155_900 * 1e6;

    // ─── Placeholder: Uniswap NFT manager deadline for `executeMigration` ────
    uint256 public migrationDeadline;

    /// @dev Set before `run()` or fork tests. Edit state vars directly before production `forge script` if preferred.
    function setMigrationConfig(address migrationHelper_, uint256 migrationDeadline_) external {
        migrationHelper = migrationHelper_;
        migrationDeadline = migrationDeadline_;
    }

    function run() public {
        uint256 usdcUsmLiquidity = IUsm(USDC_USM).getAvailableLiquidity();
        uint256 dusdRequired = usdcUsmLiquidity * USDC_TO_FRXUSD_SCALE;
        uint256 deadline = migrationDeadline == 0 ? block.timestamp + 24 hours : migrationDeadline;

        require(migrationHelper != address(0), "set migrationHelper before running");

        console.log("=== Deprecate USDC USM & Execute DUSD Pool Migration ===");
        console.log("Treasury:", TREASURY);
        console.log("USDC USM available liquidity:", usdcUsmLiquidity);
        console.log("USDC required to source DUSD via frxUSD USM:", usdcUsmLiquidity);
        console.log("DUSD sourced then spent on USDC USM buy:", dusdRequired);
        console.log("Migration helper:", migrationHelper);
        console.log("Migration deadline:", deadline);
        console.log("");

        (address[] memory targets, bytes[] memory payloads) = _buildMigrationTransactions(usdcUsmLiquidity, deadline);
        _logTransactions(targets, payloads);
        _writeSafeBatchJson(SAFE_TX_NAME, targets, payloads);
    }

    function _buildMigrationTransactions(uint256 usdcUsmLiquidity, uint256 deadline)
        internal
        view
        returns (address[] memory targets, bytes[] memory payloads)
    {
        uint256 frxUsdAmount = usdcUsmLiquidity * USDC_TO_FRXUSD_SCALE;

        DusdPoolMigrationHelper.DrainMins memory drainMins = DusdPoolMigrationHelper.DrainMins({
            minExpectedDusdFromNarrowPosition: minExpectedDusdFromNarrowPosition,
            minExpectedUsdcFromNarrowPosition: minExpectedUsdcFromNarrowPosition,
            minExpectedDusdFromWidePosition: minExpectedDusdFromWidePosition,
            minExpectedUsdcFromWidePosition: minExpectedUsdcFromWidePosition
        });

        targets = new address[](TX_COUNT);
        payloads = new bytes[](TX_COUNT);

        targets[0] = USDC_MAINNET;
        payloads[0] = abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, usdcUsmLiquidity);

        targets[1] = FRAX_CUSTODIAN;
        payloads[1] = abi.encodeWithSelector(IERC4626.deposit.selector, usdcUsmLiquidity, TREASURY);

        targets[2] = FRXUSD_MAINNET;
        payloads[2] = abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_USM, frxUsdAmount);

        targets[3] = FRXUSD_USM;
        payloads[3] = abi.encodeWithSelector(IUsm.sellAsset.selector, frxUsdAmount, TREASURY);

        targets[4] = DUSD;
        payloads[4] = abi.encodeWithSelector(IERC20.approve.selector, USDC_USM, frxUsdAmount);

        targets[5] = USDC_USM;
        payloads[5] = abi.encodeWithSelector(IUsm.buyAsset.selector, usdcUsmLiquidity, TREASURY);

        targets[6] = UNISWAP_V3_NFT_POSITION_MANAGER;
        payloads[6] = abi.encodeWithSelector(IERC721.approve.selector, migrationHelper, NARROW_POSITION_TOKEN_ID);

        targets[7] = UNISWAP_V3_NFT_POSITION_MANAGER;
        payloads[7] = abi.encodeWithSelector(IERC721.approve.selector, migrationHelper, WIDE_POSITION_TOKEN_ID);

        targets[8] = migrationHelper;
        payloads[8] = abi.encodeWithSelector(DusdPoolMigrationHelper.executeMigration.selector, drainMins, deadline);

        targets[9] = UNISWAP_V3_NFT_POSITION_MANAGER;
        payloads[9] = abi.encodeWithSelector(IERC721.approve.selector, address(0), NARROW_POSITION_TOKEN_ID);

        targets[10] = UNISWAP_V3_NFT_POSITION_MANAGER;
        payloads[10] = abi.encodeWithSelector(IERC721.approve.selector, address(0), WIDE_POSITION_TOKEN_ID);
    }

    function _logTransactions(address[] memory targets, bytes[] memory payloads) internal pure {
        for (uint256 i = 0; i < targets.length; i++) {
            _logHeader(i + 1, _txLabel(i + 1), targets[i]);
            console.logBytes(payloads[i]);
        }
    }

    function _txLabel(uint256 txNum) internal pure returns (string memory) {
        if (txNum == 1) return "approve USDC to frax custodian (source DUSD)";
        if (txNum == 2) return "frax custodian deposit (USDC to frxUSD)";
        if (txNum == 3) return "approve frxUSD to frxUSD USM";
        if (txNum == 4) return "frxUSD USM sellAsset - source DUSD from frxUSD";
        if (txNum == 5) return "approve DUSD to USDC USM";
        if (txNum == 6) return "USDC USM buyAsset - drain liquidity to 0";
        if (txNum == 7) return "approve narrow position NFT to migration helper";
        if (txNum == 8) return "approve wide position NFT to migration helper";
        if (txNum == 9) return "DusdPoolMigrationHelper.executeMigration";
        if (txNum == 10) return "disapprove narrow position NFT from migration helper";
        if (txNum == 11) return "disapprove wide position NFT from migration helper";
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
