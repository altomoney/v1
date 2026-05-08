// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";

/// @title GenerateTreasuryMigration
/// @notice Generates a Safe Transaction Builder JSON with the full treasury PSM migration flow:
/// Run:
///   forge script script/GenerateTreasuryMigration.s.sol:GenerateTreasuryMigration --rpc-url ethereum
contract GenerateTreasuryMigration is Script {
    uint256 internal constant MARKET_COUNT = 5;
    uint256 internal constant TX_COUNT = 13;

    address constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    address constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
    address constant VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;

    address constant CBBTC_BORROW = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;
    address constant WBTC_BORROW = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
    address constant SUSDE_BORROW = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address constant SYRUPUSDC_BORROW = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant PAXG_BORROW = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817;

    uint256 constant AMOUNT = 200_000 ether;
    uint256 constant USDC_IN = 200_000e6;
    uint256 constant DUSD_FOR_USDC = 200_000 ether;
    uint256 constant USDC_OUT = 200_000e6;

    string constant OUTPUT_FILE = "contracts/deployments/ethereum-mainnet/output/safe-tx-treasury-migration.json";

    function run() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));

        address[MARKET_COUNT] memory markets = [CBBTC_BORROW, WBTC_BORROW, SUSDE_BORROW, SYRUPUSDC_BORROW, PAXG_BORROW];
        uint128[MARKET_COUNT] memory supplyShares = _loadSupplyShares(markets);
        address[] memory to = new address[](TX_COUNT);
        bytes[] memory cd = new bytes[](TX_COUNT);
        uint256 idx;

        // TX 1 – approve USDC to fraxCustodian
        to[idx] = USDC;
        cd[idx] = abi.encodeCall(IERC20.approve, (FRAX_CUSTODIAN, USDC_IN));
        ++idx;

        // TX 2 – fraxCustodian.deposit (USDC in, frxUSD out to treasury)
        to[idx] = FRAX_CUSTODIAN;
        cd[idx] = abi.encodeCall(IERC4626.deposit, (USDC_IN, TREASURY));
        ++idx;

        // TX 3 – approve frxUSD to frxUSDUsm
        to[idx] = FRXUSD;
        cd[idx] = abi.encodeCall(IERC20.approve, (FRXUSD_USM, AMOUNT));
        ++idx;

        // TX 4 – frxUSDUsm.sellAsset (frxUSD in, DUSD out to treasury)
        to[idx] = FRXUSD_USM;
        cd[idx] = abi.encodeCall(IUsm.sellAsset, (AMOUNT, TREASURY));
        ++idx;

        // TX 5 – approve DUSD to vault
        to[idx] = DUSD;
        cd[idx] = abi.encodeCall(IERC20.approve, (VAULT, AMOUNT));
        ++idx;

        // TX 6 – vault.deposit (DUSD in, vault shares to treasury)
        to[idx] = VAULT;
        cd[idx] = abi.encodeCall(IERC4626.deposit, (AMOUNT, TREASURY));
        ++idx;

        // TX 7–11 – removeSupply from each borrow market (shares → DUSD to treasury)
        for (uint256 i; i < MARKET_COUNT; ++i) {
            to[idx] = markets[i];
            cd[idx] = abi.encodeCall(IMarketBase.removeSupply, (0, uint256(supplyShares[i]), TREASURY, TREASURY));
            ++idx;
        }

        // TX 12 – approve DUSD to usdcUSM
        to[idx] = DUSD;
        cd[idx] = abi.encodeCall(IERC20.approve, (USDC_USM, DUSD_FOR_USDC));
        ++idx;

        // TX 13 – usdcUSM.buyAsset (DUSD in, USDC out to treasury)
        to[idx] = USDC_USM;
        cd[idx] = abi.encodeCall(IUsm.buyAsset, (USDC_OUT, TREASURY));

        _writeSafeBatch(to, cd);
    }

    function _loadSupplyShares(address[MARKET_COUNT] memory markets)
        internal
        view
        returns (uint128[MARKET_COUNT] memory supplyShares)
    {
        for (uint256 i; i < MARKET_COUNT; ++i) {
            supplyShares[i] = IMarket(markets[i]).position(TREASURY).supplyShares;
        }
    }

    function _writeSafeBatch(address[] memory to, bytes[] memory cd) internal {
        string memory txList;
        for (uint256 i; i < to.length; ++i) {
            string memory entry =
                string.concat('{"to":"', vm.toString(to[i]), '","value":"0","data":"', vm.toString(cd[i]), '"}');
            txList = i == 0 ? entry : string.concat(txList, ",", entry);
        }

        string memory json = string.concat(
            '{"version":"1.0","chainId":"1",',
            '"meta":{"name":"Treasury PSM Migration"},',
            '"transactions":[',
            txList,
            "]}"
        );

        vm.writeFile(OUTPUT_FILE, json);
    }
}
