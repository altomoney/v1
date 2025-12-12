// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {USDC_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title Generate USM Transaction Data
/// @notice Generates transaction data for Safe wallet bulk execution
/// @dev Inputs: Permissioned USM address, DUSD address, multisig address, USDC amount, DUSD amount
contract GenerateUsmTransactionsScript is Script {
    function run() public {
        // Get inputs interactively from user
        address permissionedUsm = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;

        address dusd = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

        address multisig = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

        uint256 usdcAmount = (55_000 + 240_000) * 10 ** 6;

        uint256 dusdAmount = IERC20(dusd).balanceOf(multisig);

        console.log("=== USM Transaction Generator (Permissioned - No Fees) ===");
        console.log("Permissioned USM Address:", permissionedUsm);
        console.log("DUSD Address:", dusd);
        console.log("USDC Address:", USDC_MAINNET);
        console.log("Multisig Address:", multisig);
        console.log("USDC Amount to Sell (raw):", usdcAmount);
        console.log("Expected DUSD Received (1:1, no fees, raw):", usdcAmount * 1e12); // Convert 6 decimals to 18 decimals
        console.log("DUSD Amount to Buy USDC (raw):", dusdAmount);
        console.log("Expected USDC Received (1:1, no fees, raw):", dusdAmount / 1e12); // Convert 18 decimals to 6 decimals

        console.log("\n=== TRANSACTION DATA FOR SAFE WALLET ===");

        {
            // Transaction 1: Approve USDC for Permissioned USM
            console.log("\n--- Transaction 1: Approve USDC for Permissioned USM ---");
            bytes memory approveUsdcData = abi.encodeWithSelector(IERC20.approve.selector, permissionedUsm, usdcAmount);
            console.log("To:", USDC_MAINNET);
            console.log("Value: 0");
            console.logBytes(approveUsdcData);
        }

        {
            // Transaction 2: Sell USDC for DUSD
            console.log("\n--- Transaction 2: Sell USDC for DUSD (No Fees) ---");
            bytes memory sellAssetData = abi.encodeWithSelector(IUsm.sellAsset.selector, usdcAmount, multisig);
            console.log("To:", permissionedUsm);
            console.log("Value: 0");
            console.logBytes(sellAssetData);
            console.log("Selling (raw):", usdcAmount);
            console.log("Expected DUSD received (1:1, no fees, raw):", usdcAmount * 1e12);
            console.log("Receiver:", multisig);
        }

        {
            // Transaction 3: Approve DUSD for Permissioned USM
            console.log("\n--- Transaction 3: Approve DUSD for Permissioned USM ---");
            bytes memory approveDusdData = abi.encodeWithSelector(IERC20.approve.selector, permissionedUsm, dusdAmount);
            console.log("To:", dusd);
            console.log("Value: 0");
            console.logBytes(approveDusdData);
        }

        {
            // Transaction 4: Buy USDC with DUSD
            console.log("\n--- Transaction 4: Buy USDC with DUSD (No Fees) ---");
            // For buyAsset, minAmount is the minimum USDC to receive
            // Permissioned USM has no fees, so 1:1 exchange rate
            // dusdAmount (18 decimals) = usdcAmount (6 decimals) * 1e12
            uint256 expectedUsdc = dusdAmount / 1e12; // Convert from 18 to 6 decimals (1:1 price, no fees)
            // Use expected amount as minAmount since there are no fees (exact 1:1 exchange)
            uint256 minUsdcAmount = expectedUsdc;
            bytes memory buyAssetData = abi.encodeWithSelector(IUsm.buyAsset.selector, minUsdcAmount, multisig);
            console.log("To:", permissionedUsm);
            console.log("Value: 0");
            console.logBytes(buyAssetData);
            console.log("Min USDC to receive (1:1, no fees, raw):", minUsdcAmount);
            console.log("DUSD amount to spend (raw):", dusdAmount);
            console.log("Expected USDC received (1:1, no fees, raw):", expectedUsdc);
            console.log("Receiver:", multisig);
        }
    }
}

