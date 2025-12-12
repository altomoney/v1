// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USDC_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {
    INonfungiblePositionManager,
    MintParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";

/// @title Generate DUSD/USDC Pool Deployment Transaction Data
/// @notice Generates transaction data for Safe wallet bulk execution
/// @dev Inputs: DUSD address, multisig address
contract GenerateDusdUsdcPoolTransactionsScript is Script {
    address constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint24 constant FEE_100 = 100; // 0.01%
    uint256 constant SLIPPAGE_BPS = 100; // 1% slippage tolerance

    // Position amounts (from test)
    uint256 constant POSITION_1_DUSD = 239999 ether;
    uint256 constant POSITION_1_USDC = 944202 * 1e6;
    uint256 constant POSITION_2_DUSD = 54641 ether;
    uint256 constant POSITION_2_USDC = 240_000 * 1e6;

    // Tick offsets from base tick (from test)
    int24 constant POS_1_LOWER_OFFSET = -7; // 0.9993
    int24 constant POS_1_UPPER_OFFSET = 3; // 1.0003
    int24 constant POS_2_LOWER_OFFSET = -304; // 0.97
    int24 constant POS_2_UPPER_OFFSET = 70; // 1.007

    function run() public {
        // Get inputs interactively from user
        address dusd = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

        address multisig = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

        // Deadline: use env var if provided, otherwise use 1 year from now
        uint256 deadline = block.timestamp + 3 hours;

        console.log("=== DUSD/USDC Pool Deployment Transaction Generator ===");
        console.log("DUSD Address:", dusd);
        console.log("Multisig Address:", multisig);
        console.log("USDC Address:", USDC_MAINNET);
        console.log("Deadline timestamp:", deadline);

        // Determine token ordering
        bool dusdIsToken0 = dusd < USDC_MAINNET;
        address token0 = dusdIsToken0 ? dusd : USDC_MAINNET;
        address token1 = dusdIsToken0 ? USDC_MAINNET : dusd;

        console.log("\nToken Ordering:");
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("DUSD is Token0:", dusdIsToken0);

        // Calculate sqrtPriceX96 for 1:1 price
        uint160 sqrtPriceX96 = _getSqrtPriceX96ForOneToOne(dusdIsToken0);
        console.log("\nsqrtPriceX96:", sqrtPriceX96);

        // Calculate base tick manually (as done in test)
        // For 1:1 price with 18 vs 6 decimals:
        // If DUSD is token0: price = 1e6/1e18 = 1e-12, tick ≈ log(1e-12) / log(1.0001) ≈ -276325
        // If DUSD is token1: price = 1e18/1e6 = 1e12, tick ≈ log(1e12) / log(1.0001) ≈ 276324
        int24 baseTick = dusdIsToken0 ? int24(-276325) : int24(276324);
        console.log("Base tick:");
        console.logInt(baseTick);

        // Generate transaction data
        _generateAllTransactions(dusd, token0, token1, sqrtPriceX96, baseTick, dusdIsToken0, multisig, deadline);
    }

    /// @notice Calculate sqrtPriceX96 for 1:1 price
    function _getSqrtPriceX96ForOneToOne(bool dusdIsToken0) internal pure returns (uint160) {
        uint256 Q96 = 2 ** 96;
        if (dusdIsToken0) {
            // price = USDC/DUSD in raw = 1e6/1e18 = 1e-12
            // sqrt(1e-12) = 1e-6
            return uint160(Q96 / 1e6);
        } else {
            // price = DUSD/USDC in raw = 1e18/1e6 = 1e12
            // sqrt(1e12) = 1e6
            return uint160(Q96 * 1e6);
        }
    }

    /// @notice Generate all transactions
    function _generateAllTransactions(
        address dusd_,
        address token0_,
        address token1_,
        uint160 sqrtPriceX96_,
        int24 baseTick_,
        bool dusdIsToken0_,
        address multisig_,
        uint256 deadline_
    ) internal pure {
        console.log("\n=== TRANSACTION DATA FOR SAFE WALLET ===");
        console.log("\n--- Transaction 1: Approve DUSD ---");
        bytes memory approveDusdData = abi.encodeWithSelector(
            IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, POSITION_1_DUSD + POSITION_2_DUSD
        );
        console.log("To:", dusd_);
        console.log("Value: 0");
        console.logBytes(approveDusdData);

        console.log("\n--- Transaction 2: Approve USDC ---");
        bytes memory approveUsdcData = abi.encodeWithSelector(
            IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, POSITION_1_USDC + POSITION_2_USDC
        );
        console.log("To:", USDC_MAINNET);
        console.log("Value: 0");
        console.logBytes(approveUsdcData);

        console.log("\n--- Transaction 3: Create and Initialize Pool ---");
        bytes memory createPoolData = abi.encodeWithSelector(
            INonfungiblePositionManager.createAndInitializePoolIfNecessary.selector,
            token0_,
            token1_,
            FEE_100,
            sqrtPriceX96_
        );
        console.log("To:", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.log("Value: 0");
        console.logBytes(createPoolData);
        {
            // Calculate position ticks
            int24 pos1Lower = baseTick_ + POS_1_LOWER_OFFSET;
            int24 pos1Upper = baseTick_ + POS_1_UPPER_OFFSET;

            console.log("\nPosition 1 ticks:");
            console.logInt(pos1Lower);
            console.logInt(pos1Upper);
            _generatePosition(
                "\n--- Transaction 4: Mint Position 1 (Tight Range) ---",
                token0_,
                token1_,
                pos1Lower,
                pos1Upper,
                dusdIsToken0_,
                POSITION_1_DUSD,
                POSITION_1_USDC,
                multisig_,
                deadline_
            );
        }
        {

            int24 pos2Lower = baseTick_ + POS_2_LOWER_OFFSET;
            int24 pos2Upper = baseTick_ + POS_2_UPPER_OFFSET;
            console.log("Position 2 ticks:");
            console.logInt(pos2Lower);
            console.logInt(pos2Upper);
            _generatePosition(
                "\n--- Transaction 5: Mint Position 2 (Wide Range) ---",
                token0_,
                token1_,
                pos2Lower,
                pos2Upper,
                dusdIsToken0_,
                POSITION_2_DUSD,
                POSITION_2_USDC,
                multisig_,
                deadline_
            );
        }
    }

    /// @notice Generate mint transaction for a liquidity position
    function _generatePosition(
        string memory transactionTitle,
        address token0_,
        address token1_,
        int24 tickLower,
        int24 tickUpper,
        bool dusdIsToken0_,
        uint256 dusdAmount,
        uint256 usdcAmount,
        address recipient,
        uint256 deadline_
    ) internal pure {
        console.log(transactionTitle);

        uint256 amount0Desired = dusdIsToken0_ ? dusdAmount : usdcAmount;
        uint256 amount1Desired = dusdIsToken0_ ? usdcAmount : dusdAmount;

        uint256 amount0Min = amount0Desired * (10_000 - SLIPPAGE_BPS) / 10_000;
        uint256 amount1Min = amount1Desired * (10_000 - SLIPPAGE_BPS) / 10_000;

        MintParams memory params = MintParams({
            token0: token0_,
            token1: token1_,
            fee: FEE_100,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: recipient,
            deadline: deadline_
        });

        bytes memory mintData = abi.encodeWithSelector(INonfungiblePositionManager.mint.selector, params);

        console.log("To:", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.log("Value: 0");
        console.logBytes(mintData);
        console.log("Expected amounts:");
        if (dusdIsToken0_) {
            console.log("  DUSD (token0):", dusdAmount / 1e18);
            console.log("  USDC (token1):", usdcAmount / 1e6);
        } else {
            console.log("  USDC (token0):", usdcAmount / 1e6);
            console.log("  DUSD (token1):", dusdAmount / 1e18);
        }
    }
}

