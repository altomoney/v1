// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMarketBase} from "contracts/lending/interfaces/IMarket.sol";

/// @title Generate DUSD Rebalance Transactions
/// @notice Logs calldata for Safe to withdraw DUSD from wBTC/cbBTC markets and supply to syrupUSDC market.
contract GenerateDusdRebalanceTransactions is Script {
    function run() public {
        address dusd = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
        address multisig = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

        // Borrow markets (DUSD as borrow token)
        address wbtcBorrowMarket = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
        address cbbtcBorrowMarket = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;
        address syrupUsdcBorrowMarket = 0x33B24510233281350bF8679A7c427d04db0ed208;

        // Amounts
        uint256 dusdFromWbtc = 20_000 * 1e18; // 18 decimals
        uint256 dusdFromCbbtc = 25_000 * 1e18; // 18 decimals
        uint256 dusdToSyrupUsdc = 45_000 * 1e18; // 18 decimals (total from both withdrawals)

        console.log("=== DUSD Rebalance Transaction Generator ===");
        console.log("DUSD:", dusd);
        console.log("Multisig:", multisig);
        console.log("WBTC Borrow Market:", wbtcBorrowMarket);
        console.log("cbBTC Borrow Market:", cbbtcBorrowMarket);
        console.log("syrupUSDC Borrow Market:", syrupUsdcBorrowMarket);
        console.log("DUSD to withdraw from WBTC (raw):", dusdFromWbtc);
        console.log("DUSD to withdraw from cbBTC (raw):", dusdFromCbbtc);
        console.log("DUSD to supply to syrupUSDC (raw):", dusdToSyrupUsdc);

        console.log("\n=== TRANSACTION DATA ===");

        {
            console.log("\n--- Tx1: Remove 20k DUSD supply from WBTC Borrow Market ---");
            bytes memory removeSupplyWbtc =
                abi.encodeWithSelector(IMarketBase.removeSupply.selector, dusdFromWbtc, 0, multisig, multisig);
            console.log("To:", wbtcBorrowMarket);
            console.log("Value: 0");
            console.logBytes(removeSupplyWbtc);
        }

        {
            console.log("\n--- Tx2: Remove 25k DUSD supply from cbBTC Borrow Market ---");
            bytes memory removeSupplyCbbtc =
                abi.encodeWithSelector(IMarketBase.removeSupply.selector, dusdFromCbbtc, 0, multisig, multisig);
            console.log("To:", cbbtcBorrowMarket);
            console.log("Value: 0");
            console.logBytes(removeSupplyCbbtc);
        }

        {
            console.log("\n--- Tx3: Approve 45k DUSD to syrupUSDC Borrow Market ---");
            bytes memory approveDusdSyrupUsdc =
                abi.encodeWithSelector(IERC20.approve.selector, syrupUsdcBorrowMarket, dusdToSyrupUsdc);
            console.log("To:", dusd);
            console.log("Value: 0");
            console.logBytes(approveDusdSyrupUsdc);
        }

        {
            console.log("\n--- Tx4: Supply 45k DUSD to syrupUSDC Borrow Market ---");
            bytes memory addSupplySyrupUsdc =
                abi.encodeWithSelector(IMarketBase.addSupply.selector, dusdToSyrupUsdc, 0, multisig);
            console.log("To:", syrupUsdcBorrowMarket);
            console.log("Value: 0");
            console.logBytes(addSupplySyrupUsdc);
        }
    }
}
