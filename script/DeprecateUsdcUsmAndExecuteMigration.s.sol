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
contract DeprecateUsdcUsmAndExecuteMigrationScript is Script {
    uint256 private constant USDC_TO_FRXUSD_SCALE = 1e12;

    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address public constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
    address public constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address public constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;
    address public constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    uint256 public constant NARROW_POSITION_TOKEN_ID = 1150307;
    uint256 public constant WIDE_POSITION_TOKEN_ID = 1150308;

    // ─── Placeholder: set deployed helper address before generating Tx 7-9 ─────
    address public migrationHelper = address(0x0A50f3f1aDc0463062D34b846d53618d2F2a30Ee);

    // ─── Placeholder: slippage floors for `decreaseLiquidity` on old positions ─
    uint256 public minExpectedDusdFromNarrowPosition = 230_000 ether;
    uint256 public minExpectedUsdcFromNarrowPosition = 540_000 * 1e6;
    uint256 public minExpectedDusdFromWidePosition = 35_000 ether;
    uint256 public minExpectedUsdcFromWidePosition = 155_000 * 1e6;

    // ─── Placeholder: Uniswap NFT manager deadline for `executeMigration` ────
    uint256 public migrationDeadline;

    /// @dev Set before `run()` or fork tests. Edit state vars directly before production `forge script` if preferred.
    function setMigrationConfig(address migrationHelper_, uint256 migrationDeadline_) external {
        migrationHelper = migrationHelper_;
        migrationDeadline = migrationDeadline_;
    }

    function run() public view {
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

        _logDeprecateUsdcUsm(usdcUsmLiquidity);
        _logApprovePositionsToHelper();
        _logExecuteMigration(deadline);
        _logDisapprovePositionsFromHelper();
    }

    function _logDeprecateUsdcUsm(uint256 usdcUsmLiquidity) internal pure {
        uint256 frxUsdAmount = usdcUsmLiquidity * USDC_TO_FRXUSD_SCALE;

        _logHeader(1, "approve USDC to frax custodian (source DUSD)", USDC_MAINNET);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, usdcUsmLiquidity));

        _logHeader(2, "frax custodian deposit (USDC to frxUSD)", FRAX_CUSTODIAN);
        console.logBytes(abi.encodeWithSelector(IERC4626.deposit.selector, usdcUsmLiquidity, TREASURY));

        _logHeader(3, "approve frxUSD to frxUSD USM", FRXUSD_MAINNET);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_USM, frxUsdAmount));

        _logHeader(4, "frxUSD USM sellAsset - source DUSD from frxUSD", FRXUSD_USM);
        console.logBytes(abi.encodeWithSelector(IUsm.sellAsset.selector, frxUsdAmount, TREASURY));

        _logHeader(5, "approve DUSD to USDC USM", DUSD);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, USDC_USM, frxUsdAmount));

        _logHeader(6, "USDC USM buyAsset - drain liquidity to 0", USDC_USM);
        console.logBytes(abi.encodeWithSelector(IUsm.buyAsset.selector, usdcUsmLiquidity, TREASURY));
    }

    function _logApprovePositionsToHelper() internal view {
        require(migrationHelper != address(0), "set migrationHelper before logging position approve txs");

        _logHeader(7, "approve narrow position NFT to migration helper", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(abi.encodeWithSelector(IERC721.approve.selector, migrationHelper, NARROW_POSITION_TOKEN_ID));

        _logHeader(8, "approve wide position NFT to migration helper", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(abi.encodeWithSelector(IERC721.approve.selector, migrationHelper, WIDE_POSITION_TOKEN_ID));
    }

    function _logExecuteMigration(uint256 deadline) internal view {
        require(migrationHelper != address(0), "set migrationHelper before logging executeMigration tx");

        DusdPoolMigrationHelper.DrainMins memory drainMins = DusdPoolMigrationHelper.DrainMins({
            minExpectedDusdFromNarrowPosition: minExpectedDusdFromNarrowPosition,
            minExpectedUsdcFromNarrowPosition: minExpectedUsdcFromNarrowPosition,
            minExpectedDusdFromWidePosition: minExpectedDusdFromWidePosition,
            minExpectedUsdcFromWidePosition: minExpectedUsdcFromWidePosition
        });

        _logHeader(9, "DusdPoolMigrationHelper.executeMigration", migrationHelper);
        console.logBytes(abi.encodeWithSelector(DusdPoolMigrationHelper.executeMigration.selector, drainMins, deadline));
    }

    function _logDisapprovePositionsFromHelper() internal view {
        require(migrationHelper != address(0), "set migrationHelper before logging position disapprove txs");

        _logHeader(10, "disapprove narrow position NFT from migration helper", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(abi.encodeWithSelector(IERC721.approve.selector, address(0), NARROW_POSITION_TOKEN_ID));

        _logHeader(11, "disapprove wide position NFT from migration helper", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(abi.encodeWithSelector(IERC721.approve.selector, address(0), WIDE_POSITION_TOKEN_ID));
    }

    function _logHeader(uint256 txNum, string memory label, address to) internal pure {
        console.log(string.concat("--- Tx ", vm.toString(txNum), " | ", label, " ---"));
        console.log("To:", to);
    }
}
