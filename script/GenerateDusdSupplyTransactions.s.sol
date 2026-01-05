// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IMarketBase} from "contracts/lending/interfaces/IMarket.sol";
import {USDC_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title Generate DUSD Supply Transactions
/// @notice Logs calldata for Safe to sell USDC for DUSD on permissioned USM and supply DUSD into borrow markets.
contract GenerateDusdSupplyTransactions is Script {
    function run() public {
        address permissionedUsm = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
        address dusd = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
        address multisig = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

        // Borrow markets (DUSD as borrow token)
        address wbtcBorrowMarket = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
        address cbbtcBorrowMarket = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;
        address susdeBorrowMarket = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;

        // Amounts
        uint256 usdcAmount = 200_000 * 1e6; // 6 decimals
        uint256 dusdToWbtc = 50_000 * 1e18; // 18 decimals
        uint256 dusdToCbbtc = 50_000 * 1e18; // 18 decimals
        uint256 dusdToSusde = 100_000 * 1e18; // 18 decimals

        console.log("=== DUSD Supply Transaction Generator ===");
        console.log("Permissioned USM:", permissionedUsm);
        console.log("DUSD:", dusd);
        console.log("USDC:", USDC_MAINNET);
        console.log("Multisig:", multisig);
        console.log("WBTC Borrow Market:", wbtcBorrowMarket);
        console.log("cbBTC Borrow Market:", cbbtcBorrowMarket);
        console.log("sUSDe Borrow Market:", susdeBorrowMarket);
        console.log("USDC Amount (raw):", usdcAmount);
        console.log("DUSD Amount (raw) - WBTC:", dusdToWbtc);
        console.log("DUSD Amount (raw) - cbBTC:", dusdToCbbtc);
        console.log("DUSD Amount (raw) - sUSDe:", dusdToSusde);

        console.log("\n=== TRANSACTION DATA ===");

        {
            console.log("\n--- Tx1: Approve USDC for Permissioned USM ---");
            bytes memory approveUsdcData = abi.encodeWithSelector(IERC20.approve.selector, permissionedUsm, usdcAmount);
            console.log("To:", USDC_MAINNET);
            console.log("Value: 0");
            console.logBytes(approveUsdcData);
        }

        {
            console.log("\n--- Tx2: Sell 200k USDC for DUSD on Permissioned USM ---");
            bytes memory sellUsdcData = abi.encodeWithSelector(IUsm.sellAsset.selector, usdcAmount, multisig);
            console.log("To:", permissionedUsm);
            console.log("Value: 0");
            console.logBytes(sellUsdcData);
            console.log("Selling (raw):", usdcAmount);
            console.log("Expected DUSD received (1:1, no fees, raw):", usdcAmount * 1e12);
            console.log("Receiver:", multisig);
        }

        {
            console.log("\n--- Tx3: Approve 50k DUSD to WBTC Borrow Market ---");
            bytes memory approveDusdWbtc = abi.encodeWithSelector(IERC20.approve.selector, wbtcBorrowMarket, dusdToWbtc);
            console.log("To:", dusd);
            console.log("Value: 0");
            console.logBytes(approveDusdWbtc);
        }

        {
            console.log("\n--- Tx4: Approve 50k DUSD to cbBTC Borrow Market ---");
            bytes memory approveDusdCbbtc =
                abi.encodeWithSelector(IERC20.approve.selector, cbbtcBorrowMarket, dusdToCbbtc);
            console.log("To:", dusd);
            console.log("Value: 0");
            console.logBytes(approveDusdCbbtc);
        }

        {
            console.log("\n--- Tx5: Approve 100k DUSD to sUSDe Borrow Market ---");
            bytes memory approveDusdSusde =
                abi.encodeWithSelector(IERC20.approve.selector, susdeBorrowMarket, dusdToSusde);
            console.log("To:", dusd);
            console.log("Value: 0");
            console.logBytes(approveDusdSusde);
        }

        {
            console.log("\n--- Tx6: Supply 50k DUSD to WBTC Borrow Market ---");
            bytes memory addSupplyWbtc = abi.encodeWithSelector(IMarketBase.addSupply.selector, dusdToWbtc, 0, multisig);
            console.log("To:", wbtcBorrowMarket);
            console.log("Value: 0");
            console.logBytes(addSupplyWbtc);
        }

        {
            console.log("\n--- Tx7: Supply 50k DUSD to cbBTC Borrow Market ---");
            bytes memory addSupplyCbbtc =
                abi.encodeWithSelector(IMarketBase.addSupply.selector, dusdToCbbtc, 0, multisig);
            console.log("To:", cbbtcBorrowMarket);
            console.log("Value: 0");
            console.logBytes(addSupplyCbbtc);
        }

        {
            console.log("\n--- Tx8: Supply 100k DUSD to sUSDe Borrow Market ---");
            bytes memory addSupplySusde =
                abi.encodeWithSelector(IMarketBase.addSupply.selector, dusdToSusde, 0, multisig);
            console.log("To:", susdeBorrowMarket);
            console.log("Value: 0");
            console.logBytes(addSupplySusde);
        }
    }
}

