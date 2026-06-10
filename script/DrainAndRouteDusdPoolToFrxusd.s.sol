// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {
    INonfungiblePositionManager,
    DecreaseLiquidityParams,
    CollectParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title Drain DUSD/USDC Pool & Route Through PSMs
/// @notice Generates Safe wallet calldata for draining the old Uniswap positions
///         and routing tokens through USDC/frxUSD USMs and the frax custodian.
///         Run this script before `MigrateDusdPoolToFrxusd.s.sol`.
///
///         Flow (10 transactions):
///           1-4   drain & collect both old positions
///           5-10  route DUSD → USDC (drain USDC USM) → frxUSD (custodian) → DUSD (frxUSD USM)
contract DrainAndRouteDusdPoolToFrxusdScript is Script {
    address constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    /// @dev Existing DUSD/USDC 0.01% pool. DUSD (0x63..) is token0, USDC (0xA0..) is token1.
    address constant EXISTING_POOL = 0x206239406AbcCf730493e4b133b30df546F9Ff43;

    /// @dev ERC-4626 custodian vault: deposit(usdcAmount, receiver) → frxUSD (1:1 dollar, 1e6→1e18)
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    /// @dev Permissioned USMs (treasury holds SWAPPER_ROLE). 1:1, zero fee strategy.
    address constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
    address constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;

    uint256 constant POS1_TOKEN_ID = 1150307;
    uint256 constant POS2_TOKEN_ID = 1150308;

    // ─── Drain old positions (Tx 1-2) — 1% slippage on expected collect amounts ─
    uint256 public drainPos1DusdMin = 230_000 ether;
    uint256 public drainPos1UsdcMin = 540_000 * 1e6;
    uint256 public drainPos2DusdMin = 35_000 ether;
    uint256 public drainPos2UsdcMin = 155_000 * 1e6;

    function run() public view {
        uint256 deadline = block.timestamp + 3 hours;

        console.log("=== Drain DUSD/USDC Pool & Route Through PSMs ===");
        console.log("Old pool:", EXISTING_POOL);
        console.log("Deadline:", deadline);
        console.log("");

        _logDrainAndCollect(deadline);
        _logRouteThroughPsms();
    }

    function _logDrainAndCollect(uint256 deadline) internal view {
        INonfungiblePositionManager nftMgr = INonfungiblePositionManager(UNISWAP_V3_NFT_POSITION_MANAGER);
        (,,,,,,, uint128 pos1Liquidity,,,,) = nftMgr.positions(POS1_TOKEN_ID);
        (,,,,,,, uint128 pos2Liquidity,,,,) = nftMgr.positions(POS2_TOKEN_ID);

        _logHeader(1, "decreaseLiquidity (pos 1150307)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.decreaseLiquidity.selector,
                DecreaseLiquidityParams({
                    tokenId: POS1_TOKEN_ID,
                    liquidity: pos1Liquidity,
                    amount0Min: drainPos1DusdMin,
                    amount1Min: drainPos1UsdcMin,
                    deadline: deadline
                })
            )
        );

        _logHeader(2, "decreaseLiquidity (pos 1150308)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.decreaseLiquidity.selector,
                DecreaseLiquidityParams({
                    tokenId: POS2_TOKEN_ID,
                    liquidity: pos2Liquidity,
                    amount0Min: drainPos2DusdMin,
                    amount1Min: drainPos2UsdcMin,
                    deadline: deadline
                })
            )
        );

        _logHeader(3, "collect (pos 1150307)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.collect.selector,
                CollectParams({
                    tokenId: POS1_TOKEN_ID,
                    recipient: TREASURY,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            )
        );

        _logHeader(4, "collect (pos 1150308)", UNISWAP_V3_NFT_POSITION_MANAGER);
        console.logBytes(
            abi.encodeWithSelector(
                INonfungiblePositionManager.collect.selector,
                CollectParams({
                    tokenId: POS2_TOKEN_ID,
                    recipient: TREASURY,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            )
        );
    }

    function _logRouteThroughPsms() internal view {
        uint256 usdcUsmLiquidity = IUsm(USDC_USM).getAvailableLiquidity();

        _logHeader(5, "approve DUSD to USDC USM", DUSD);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, USDC_USM, usdcUsmLiquidity * 1e12));

        _logHeader(6, "USDC USM buyAsset - drain liquidity to 0", USDC_USM);
        console.logBytes(abi.encodeWithSelector(IUsm.buyAsset.selector, usdcUsmLiquidity, TREASURY));

        _logHeader(7, "approve USDC to fraxCustodian to get back DUSD", USDC_MAINNET);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, usdcUsmLiquidity));

        _logHeader(8, "fraxCustodian.deposit", FRAX_CUSTODIAN);
        console.logBytes(abi.encodeWithSelector(IERC4626.deposit.selector, usdcUsmLiquidity, TREASURY));

        _logHeader(9, "approve frxUSD to frxUSD USM", FRXUSD_MAINNET);
        console.logBytes(abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_USM, usdcUsmLiquidity * 1e12));

        _logHeader(10, "frxUSD USM sellAsset - frxUSD to DUSD", FRXUSD_USM);
        console.logBytes(abi.encodeWithSelector(IUsm.sellAsset.selector, usdcUsmLiquidity * 1e12, TREASURY));
    }

    function _logHeader(uint256 txNum, string memory label, address to) internal pure {
        console.log(string.concat("--- Tx ", vm.toString(txNum), " | ", label, " ---"));
        console.log("To:", to);
    }
}
