// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    INonfungiblePositionManager,
    MintParams,
    DecreaseLiquidityParams,
    CollectParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title DUSD/USDC → DUSD/frxUSD pool migration helper
/// @notice Executes removal of liquidity from the old DUSD/USDC pool, deploys the new DUSD/frxUSD pool,
///      and sends any remaining DUSD, frxUSD, or USDC balances to treasury.
contract DusdPoolMigrationHelper is Ownable {
    using SafeERC20 for IERC20;

    uint256 private constant USDC_TO_FRXUSD_SCALE = 1e12;
    uint256 private constant Q96 = 1 << 96;
    uint256 private constant NARROW_POSITION_SLIPPAGE = 70;
    uint256 private constant WIDE_POSITION_SLIPPAGE = 90;
    uint256 private constant SLIPPAGE_PCT_DENOMINATOR = 100;

    address public constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    uint256 public constant NARROW_POSITION_TOKEN_ID = 1150307;
    uint256 public constant WIDE_POSITION_TOKEN_ID = 1150308;
    uint24 public constant POOL_FEE = 100; // same as original pool
    int24 public constant NARROW_POSITION_LOWER = -7; // 0.9993
    int24 public constant NARROW_POSITION_UPPER = 3; // 1.0003
    int24 public constant WIDE_POSITION_LOWER = -304; // 0.97
    int24 public constant WIDE_POSITION_UPPER = 70; // 1.007

    // ─── Values set after removal of liquidity from old uniswap pool(i.e. DUSD/USDC pool) and collection of tokens ───────────────────
    uint256 public dusdCollectedFromNarrowPosition;
    uint256 public usdcCollectedFromNarrowPosition;
    uint256 public dusdCollectedFromWidePosition;
    uint256 public usdcCollectedFromWidePosition;
    uint256 public totalUsdcCollectedFromOldUniswapPool;

    // ─── Set after new-pool mint ─────────────────────────────────────────────
    address public newPool;
    uint256 public newNarrowPositionTokenId;
    uint256 public newWidePositionTokenId;
    uint256 public dusdDepositedToNarrowPosition;
    uint256 public frxUsdDepositedToNarrowPosition;
    uint256 public dusdDepositedToWidePosition;
    uint256 public frxUsdDepositedToWidePosition;

    // ─── Set after sending remaining balances to treasury ──────────────────────
    uint256 public dusdSentToTreasury;
    uint256 public frxUsdSentToTreasury;
    uint256 public usdcSentToTreasury;

    struct DrainMins {
        uint256 minExpectedDusdFromNarrowPosition;
        uint256 minExpectedUsdcFromNarrowPosition;
        uint256 minExpectedDusdFromWidePosition;
        uint256 minExpectedUsdcFromWidePosition;
    }

    event MigrationExecuted(
        address indexed owner,
        address newPool,
        uint256 newNarrowPositionTokenId,
        uint256 newWidePositionTokenId,
        uint256 dusdSentToTreasury,
        uint256 frxUsdSentToTreasury,
        uint256 usdcSentToTreasury
    );

    constructor(address ownerAddress) Ownable(ownerAddress) {}

    /// @notice Recover full `token` balance to owner (treasury).
    /// @return amount Amount transferred to owner.
    function recoverERC20(address token) external onlyOwner returns (uint256 amount) {
        amount = IERC20(token).balanceOf(address(this));
        if (amount > 0) IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Drain old positions, deploy new pool LP, and send remaining balances to treasury.
    /// @param drainMins Slippage floors for `decreaseLiquidity` on each old position.
    /// @param deadline Uniswap NFT manager deadline for all liquidity ops in this migration.
    function executeMigration(DrainMins calldata drainMins, uint256 deadline) external onlyOwner {
        INonfungiblePositionManager uniswapPositionManager =
            INonfungiblePositionManager(UNISWAP_V3_NFT_POSITION_MANAGER);

        _drainAndCollect(uniswapPositionManager, drainMins, deadline);
        _deployNewPoolLp(uniswapPositionManager, deadline);
        _sendRemainingBalancesToTreasury();

        emit MigrationExecuted(
            owner(),
            newPool,
            newNarrowPositionTokenId,
            newWidePositionTokenId,
            dusdSentToTreasury,
            frxUsdSentToTreasury,
            usdcSentToTreasury
        );
    }

    function _drainAndCollect(
        INonfungiblePositionManager uniswapPositionManager,
        DrainMins calldata drainMins,
        uint256 deadline
    ) internal {
        (,,,,,,, uint128 narrowPositionLiquidity,,,,) = uniswapPositionManager.positions(NARROW_POSITION_TOKEN_ID);
        (,,,,,,, uint128 widePositionLiquidity,,,,) = uniswapPositionManager.positions(WIDE_POSITION_TOKEN_ID);

        uniswapPositionManager.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: NARROW_POSITION_TOKEN_ID,
                liquidity: narrowPositionLiquidity,
                amount0Min: drainMins.minExpectedDusdFromNarrowPosition,
                amount1Min: drainMins.minExpectedUsdcFromNarrowPosition,
                deadline: deadline
            })
        );
        uniswapPositionManager.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: WIDE_POSITION_TOKEN_ID,
                liquidity: widePositionLiquidity,
                amount0Min: drainMins.minExpectedDusdFromWidePosition,
                amount1Min: drainMins.minExpectedUsdcFromWidePosition,
                deadline: deadline
            })
        );

        (dusdCollectedFromNarrowPosition, usdcCollectedFromNarrowPosition) = uniswapPositionManager.collect(
            CollectParams({
                tokenId: NARROW_POSITION_TOKEN_ID,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        (dusdCollectedFromWidePosition, usdcCollectedFromWidePosition) = uniswapPositionManager.collect(
            CollectParams({
                tokenId: WIDE_POSITION_TOKEN_ID,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        totalUsdcCollectedFromOldUniswapPool = usdcCollectedFromNarrowPosition + usdcCollectedFromWidePosition;
    }

    function _deployNewPoolLp(INonfungiblePositionManager uniswapPositionManager, uint256 deadline) internal {
        IERC20(USDC_MAINNET).forceApprove(FRAX_CUSTODIAN, totalUsdcCollectedFromOldUniswapPool);
        IERC4626(FRAX_CUSTODIAN).deposit(totalUsdcCollectedFromOldUniswapPool, address(this));
        IERC20(USDC_MAINNET).forceApprove(FRAX_CUSTODIAN, 0);

        // price is set to 1:1 and hence sqrtPriceQ96 is Q96
        newPool =
            uniswapPositionManager.createAndInitializePoolIfNecessary(DUSD, FRXUSD_MAINNET, POOL_FEE, uint160(Q96));

        uint256 narrowFrxUsdDesired = usdcCollectedFromNarrowPosition * USDC_TO_FRXUSD_SCALE;
        IERC20(DUSD).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, dusdCollectedFromNarrowPosition);
        IERC20(FRXUSD_MAINNET).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, narrowFrxUsdDesired);
        (newNarrowPositionTokenId,, dusdDepositedToNarrowPosition, frxUsdDepositedToNarrowPosition) =
            uniswapPositionManager.mint(
                MintParams({
                    token0: DUSD,
                    token1: FRXUSD_MAINNET,
                    fee: POOL_FEE,
                    tickLower: NARROW_POSITION_LOWER,
                    tickUpper: NARROW_POSITION_UPPER,
                    amount0Desired: dusdCollectedFromNarrowPosition,
                    amount1Desired: narrowFrxUsdDesired,
                    amount0Min: _minAmountForSlippage(dusdCollectedFromNarrowPosition, NARROW_POSITION_SLIPPAGE),
                    amount1Min: _minAmountForSlippage(narrowFrxUsdDesired, NARROW_POSITION_SLIPPAGE),
                    recipient: owner(),
                    deadline: deadline
                })
            );

        uint256 wideFrxUsdDesired = usdcCollectedFromWidePosition * USDC_TO_FRXUSD_SCALE;
        IERC20(DUSD).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, dusdCollectedFromWidePosition);
        IERC20(FRXUSD_MAINNET).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, wideFrxUsdDesired);
        (newWidePositionTokenId,, dusdDepositedToWidePosition, frxUsdDepositedToWidePosition) =
            uniswapPositionManager.mint(
                MintParams({
                    token0: DUSD,
                    token1: FRXUSD_MAINNET,
                    fee: POOL_FEE,
                    tickLower: WIDE_POSITION_LOWER,
                    tickUpper: WIDE_POSITION_UPPER,
                    amount0Desired: dusdCollectedFromWidePosition,
                    amount1Desired: wideFrxUsdDesired,
                    amount0Min: _minAmountForSlippage(dusdCollectedFromWidePosition, WIDE_POSITION_SLIPPAGE),
                    amount1Min: _minAmountForSlippage(wideFrxUsdDesired, WIDE_POSITION_SLIPPAGE),
                    recipient: owner(),
                    deadline: deadline
                })
            );
        IERC20(DUSD).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, 0);
        IERC20(FRXUSD_MAINNET).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, 0);
    }

    /// @dev Send any remaining DUSD, frxUSD, or USDC on this contract to treasury.
    function _sendRemainingBalancesToTreasury() internal {
        dusdSentToTreasury = IERC20(DUSD).balanceOf(address(this));
        if (dusdSentToTreasury > 0) IERC20(DUSD).safeTransfer(owner(), dusdSentToTreasury);

        frxUsdSentToTreasury = IERC20(FRXUSD_MAINNET).balanceOf(address(this));
        if (frxUsdSentToTreasury > 0) IERC20(FRXUSD_MAINNET).safeTransfer(owner(), frxUsdSentToTreasury);

        usdcSentToTreasury = IERC20(USDC_MAINNET).balanceOf(address(this));
        if (usdcSentToTreasury > 0) IERC20(USDC_MAINNET).safeTransfer(owner(), usdcSentToTreasury);
    }

    function _minAmountForSlippage(uint256 desiredAmount, uint256 minPct) internal pure returns (uint256) {
        return desiredAmount * minPct / SLIPPAGE_PCT_DENOMINATOR;
    }
}
