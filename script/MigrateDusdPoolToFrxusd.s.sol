// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {
    INonfungiblePositionManager,
    MintParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title Migrate DUSD/USDC Uniswap V3 Pool to DUSD/frxUSD — LP Deployment
/// @notice Generates Safe wallet calldata for creating the new pool, minting positions,
///         and sweeping leftover frxUSD. Run after `DrainAndRouteDusdPoolToFrxusd.s.sol`.
///         Fill in the state variables below from actual balances/state during execution
///         (see fork test `test_migrateDusdUsdcToFrxusdPool` for values and derivation).
///
///         Flow (14 transactions):
///           1-2   collected USDC from Uniswap → frxUSD (custodian) for LP
///           3     create & initialize the new DUSD/frxUSD pool at 1:1
///           4-9   mint position 1 (tight) and position 2 (wide) with 1% slippage mins
///           10-14 sweep leftover frxUSD via frxUSD USM, redeposit to the narrow range
contract MigrateDusdPoolToFrxusdScript is Script {
    address public constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    /// @dev ERC-4626 custodian vault: deposit(usdcAmount, receiver) → frxUSD (1:1 dollar, 1e6→1e18)
    address public constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    /// @dev Permissioned frxUSD USM (treasury holds SWAPPER_ROLE). 1:1, zero fee strategy.
    address public constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;

    uint24 public constant FEE_100 = 100; // 0.01%
    uint256 public constant Q96 = 1 << 96; // sqrtPriceX96 at 1:1 (new pool tick 0)

    // Tick offsets are unchanged from the original positions.
    // New base tick = 0 because DUSD and frxUSD share 18 decimals (1:1 raw ⟹ tick 0).
    int24 public constant POS_1_LOWER = -7; // ≈ 0.9993
    int24 public constant POS_1_UPPER = 3; // ≈ 1.0003
    int24 public constant POS_2_LOWER = -304; // ≈ 0.97
    int24 public constant POS_2_UPPER = 70; // ≈ 1.007

    // ─── Collected from old positions (after drain script Tx 3-4) ─────────────
    uint256 public pos1DusdCollected = 235771912287694571887743;
    uint256 public pos1UsdcCollected = 545914610013;
    uint256 public pos2DusdCollected = 36581074150819610255564;
    uint256 public pos2UsdcCollected = 157881474566;

    // ─── Custodian (Tx 1-2) — fill in after drain & collect ─────────────────

    // ─── Position 1 mint — tight range [-7, +3] (Tx 4-6) ────────────────────
    uint256 public minExpectedDusdDepositPos1 = 233414192964717425868;
    uint256 public minExpectedUsdcDepositPos1 = 520000 ether;

    // ─── Position 2 mint — wide range [-304, +70] (Tx 7-9) ────────────────────
    uint256 public minExpectedDusdDepositPos2 = 362152634092914041530;
    uint256 public minExpectedUsdcDepositPos2 = 155000 ether;

    // ─── Sweep leftover frxUSD (Tx 10-14) ─────────────────────────────────────
    uint256 public frxUsdToSwapToDusd; // leftover frxUSD sold to frxUSD USM for DUSD (0 if none)
    uint256 public remainingFrxUsdToAddToLp; // leftover frxUSD minted into the narrow range (0 if none)
    uint256 public minExpectedDusdDepositNarrowRange; // 1% slippage on expected DUSD deposit
    uint256 public minExpectedFrxUsdNarrowRange; // 1% slippage on expected frxUSD deposit

    function collectedUsdcFromUniswapPool() public view returns (uint256) {
        return pos1UsdcCollected + pos2UsdcCollected;
    }

    function run() public view {
        uint256 deadline = block.timestamp + 3 hours;
        uint160 sqrtPriceX96New = uint160(Q96);

        console.log("=== DUSD/frxUSD Pool Deployment ===");
        console.log("New pool sqrtPriceX96 (1:1):", sqrtPriceX96New);
        console.log("Deadline:", deadline);
        console.log("");

        _logCustodianDeposit();
        _logCreatePool(sqrtPriceX96New);
        _logMintPositions(deadline);
        _logSweep(deadline);
    }

    // ─── Transaction logging ──────────────────────────────────────────────────

    function _logCustodianDeposit() internal view {
        uint256 usdcAmount = collectedUsdcFromUniswapPool();

        _logHeader(1, "approve USDC to fraxCustodian (collected from Uniswap)", USDC_MAINNET);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, usdcAmount));

        _logHeader(2, "fraxCustodian.deposit (collected USDC to frxUSD for LP)", FRAX_CUSTODIAN);
        console.logBytes(abi.encodeWithSelector(IERC4626.deposit.selector, usdcAmount, TREASURY));
    }

    function _logCreatePool(uint160 sqrtPriceX96New) internal view {
        _logHeader(3, "createAndInitializePoolIfNecessary (DUSD/frxUSD, fee=100)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.log("sqrtPriceX96:", sqrtPriceX96New);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.createAndInitializePoolIfNecessary.selector,
                DUSD,
                FRXUSD_MAINNET,
                FEE_100,
                sqrtPriceX96New
            )
        );
    }

    function _logMintPositions(uint256 deadline) internal view {
        _logHeader(4, "approve DUSD to NFT manager (pos1)", DUSD);
        console.logBytes(
            abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, pos1DusdCollected)
        );

        _logHeader(5, "approve frxUSD to NFT manager (pos1)", FRXUSD_MAINNET);
        console.logBytes(
            abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, pos1UsdcCollected * 1e12)
        );

        _logHeader(6, "mint position 1 (tight range, ticks -7 to +3)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.mint.selector,
                MintParams({
                    token0: DUSD,
                    token1: FRXUSD_MAINNET,
                    fee: FEE_100,
                    tickLower: POS_1_LOWER,
                    tickUpper: POS_1_UPPER,
                    amount0Desired: pos1DusdCollected,
                    amount1Desired: pos1UsdcCollected * 1e12,
                    amount0Min: minExpectedDusdDepositPos1,
                    amount1Min: minExpectedUsdcDepositPos1,
                    recipient: TREASURY,
                    deadline: deadline
                })
            )
        );

        _logHeader(7, "approve DUSD to NFT manager (pos2)", DUSD);
        console.logBytes(
            abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, pos2DusdCollected)
        );

        _logHeader(8, "approve frxUSD to NFT manager (pos2)", FRXUSD_MAINNET);
        console.logBytes(
            abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, pos2UsdcCollected * 1e12)
        );

        _logHeader(9, "mint position 2 (wide range, ticks -304 to +70)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.mint.selector,
                MintParams({
                    token0: DUSD,
                    token1: FRXUSD_MAINNET,
                    fee: FEE_100,
                    tickLower: POS_2_LOWER,
                    tickUpper: POS_2_UPPER,
                    amount0Desired: pos2DusdCollected,
                    amount1Desired: pos2UsdcCollected * 1e12,
                    amount0Min: minExpectedDusdDepositPos2,
                    amount1Min: minExpectedUsdcDepositPos2,
                    recipient: TREASURY,
                    deadline: deadline
                })
            )
        );
    }

    function _logSweep(uint256 deadline) internal view {
        _logHeader(10, "approve frxUSD to frxUSD USM (swap to DUSD)", FRXUSD_MAINNET);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_USM, frxUsdToSwapToDusd));

        _logHeader(11, "frxUSD USM sellAsset (swap to DUSD) - frxUSD to DUSD", FRXUSD_USM);
        console.logBytes(abi.encodeWithSelector(IUsm.sellAsset.selector, frxUsdToSwapToDusd, TREASURY));

        _logHeader(12, "approve DUSD to NFT manager received", DUSD);
        console.logBytes(
            abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, frxUsdToSwapToDusd)
        );

        _logHeader(13, "approve frxUSD to NFT manager (mint to narrow range)", FRXUSD_MAINNET);
        console.logBytes(
            abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_NFT_POSITION_MANAGER, remainingFrxUsdToAddToLp)
        );

        _logHeader(14, "mint narrow range position (ticks -7 to +3)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.mint.selector,
                MintParams({
                    token0: DUSD,
                    token1: FRXUSD_MAINNET,
                    fee: FEE_100,
                    tickLower: POS_1_LOWER,
                    tickUpper: POS_1_UPPER,
                    amount0Desired: frxUsdToSwapToDusd,
                    amount1Desired: remainingFrxUsdToAddToLp,
                    amount0Min: minExpectedDusdDepositNarrowRange,
                    amount1Min: minExpectedFrxUsdNarrowRange,
                    recipient: TREASURY,
                    deadline: deadline
                })
            )
        );
    }

    function _logHeader(uint256 txNum, string memory label, address to) internal pure {
        console.log(string.concat("--- Tx ", vm.toString(txNum), " | ", label, " ---"));
        console.log("To:", to);
    }
}
