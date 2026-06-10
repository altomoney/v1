// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {
    INonfungiblePositionManager,
    MintParams,
    DecreaseLiquidityParams,
    CollectParams,
    IncreaseLiquidityParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @title DUSD/USDC → DUSD/frxUSD pool migration helper
/// @notice Executes drain, PSM routing, new-pool mint, and leftover sweep in one call.
/// @dev Prerequisites before `executeMigration`:
///      1. Owner holds Uniswap V3 position NFTs (pos1/pos2 token IDs).
///      2. Owner calls `UNISWAP_V3_NFT_POSITION_MANAGER.setApprovalForAll(address(this), true)`.
///      3. Helper holds `SWAPPER_ROLE` on `USDC_USM` and `FRXUSD_USM` (calls originate from this contract).
contract DusdPoolMigrationHelper {
    using SafeERC20 for IERC20;

    /// @dev Narrow-range LP target: DUSD / frxUSD = 44 / 100 = 0.44
    uint256 private constant SWEEP_DUSD_NUM = 44;
    uint256 private constant SWEEP_DUSD_DEN = 100;
    uint256 private constant SWEEP_SUM_DEN = 144;
    uint256 private constant USDC_TO_FRXUSD_SCALE = 1e12;
    uint256 private constant MIN_SWEEP_VALUE = 10 ether;
    uint256 private constant Q96 = 1 << 96;

    address public constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
    address public constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address public constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    uint256 public constant POS1_TOKEN_ID = 1150307;
    uint256 public constant POS2_TOKEN_ID = 1150308;
    uint24 public constant POOL_FEE = 100;
    int24 public constant POS_1_LOWER = -7;
    int24 public constant POS_1_UPPER = 3;
    int24 public constant POS_2_LOWER = -304;
    int24 public constant POS_2_UPPER = 70;

    address public immutable owner;

    // ─── Set after drain & collect ───────────────────────────────────────────
    uint256 public pos1DusdCollected;
    uint256 public pos1UsdcCollected;
    uint256 public pos2DusdCollected;
    uint256 public pos2UsdcCollected;
    uint256 public collectedUsdcFromUniswapPool;

    // ─── Set after PSM routing (drain script Tx 5-10) ──────────────────────
    uint256 public usdcUsmLiquidityDrained;

    // ─── Set after new-pool mint ─────────────────────────────────────────────
    address public newPool;
    uint256 public newPos1TokenId;
    uint256 public newPos2TokenId;
    uint256 public pos1DusdDeposited;
    uint256 public pos1FrxUsdDeposited;
    uint256 public pos2DusdDeposited;
    uint256 public pos2FrxUsdDeposited;

    // ─── Set after sweep ─────────────────────────────────────────────────────
    uint256 public frxUsdToSwapToDusd;
    uint256 public remainingFrxUsdToAddToLp;
    uint256 public frxUsdToBuyFromPsm;
    uint256 public dusdForLp;
    uint256 public sweepDusdDeposited;
    uint256 public sweepFrxUsdDeposited;

    struct DrainMins {
        uint256 pos1DusdMin;
        uint256 pos1UsdcMin;
        uint256 pos2DusdMin;
        uint256 pos2UsdcMin;
    }

    event MigrationExecuted(
        address indexed owner,
        address newPool,
        uint256 newPos1TokenId,
        uint256 newPos2TokenId,
        uint256 sweepDusdDeposited,
        uint256 sweepFrxUsdDeposited
    );

    error NotOwner();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
    }

    /// @notice Drain old positions, route through PSMs, deploy new pool LP, and sweep leftovers.
    /// @param mins Slippage floors for `decreaseLiquidity` on each old position.
    function executeMigration(DrainMins calldata mins) external onlyOwner {
        uint256 deadline = block.timestamp + 3 hours;
        INonfungiblePositionManager nftMgr = INonfungiblePositionManager(UNISWAP_V3_NFT_POSITION_MANAGER);

        _drainAndCollect(nftMgr, mins, deadline);
        _routeThroughPsms();
        _deployNewPoolLp(nftMgr, deadline);
        _sweepLeftovers(nftMgr, deadline);

        emit MigrationExecuted(
            owner, newPool, newPos1TokenId, newPos2TokenId, sweepDusdDeposited, sweepFrxUsdDeposited
        );
    }

    function _drainAndCollect(
        INonfungiblePositionManager nftMgr,
        DrainMins calldata mins,
        uint256 deadline
    ) internal {
        (,,,,,,, uint128 pos1Liquidity,,,,) = nftMgr.positions(POS1_TOKEN_ID);
        (,,,,,,, uint128 pos2Liquidity,,,,) = nftMgr.positions(POS2_TOKEN_ID);

        nftMgr.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: POS1_TOKEN_ID,
                liquidity: pos1Liquidity,
                amount0Min: mins.pos1DusdMin,
                amount1Min: mins.pos1UsdcMin,
                deadline: deadline
            })
        );
        nftMgr.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: POS2_TOKEN_ID,
                liquidity: pos2Liquidity,
                amount0Min: mins.pos2DusdMin,
                amount1Min: mins.pos2UsdcMin,
                deadline: deadline
            })
        );

        (pos1DusdCollected, pos1UsdcCollected) = nftMgr.collect(
            CollectParams({
                tokenId: POS1_TOKEN_ID,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        (pos2DusdCollected, pos2UsdcCollected) = nftMgr.collect(
            CollectParams({
                tokenId: POS2_TOKEN_ID,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        collectedUsdcFromUniswapPool = pos1UsdcCollected + pos2UsdcCollected;
    }

    function _routeThroughPsms() internal {
        usdcUsmLiquidityDrained = IUsm(USDC_USM).getAvailableLiquidity();
        if (usdcUsmLiquidityDrained == 0) return;

        uint256 dusdBefore = IERC20(DUSD).balanceOf(address(this));

        IERC20(DUSD).forceApprove(USDC_USM, usdcUsmLiquidityDrained * USDC_TO_FRXUSD_SCALE);
        IUsm(USDC_USM).buyAsset(usdcUsmLiquidityDrained, address(this));

        IERC20(USDC_MAINNET).forceApprove(FRAX_CUSTODIAN, usdcUsmLiquidityDrained);
        IERC4626(FRAX_CUSTODIAN).deposit(usdcUsmLiquidityDrained, address(this));

        IERC20(FRXUSD_MAINNET).forceApprove(FRXUSD_USM, usdcUsmLiquidityDrained * USDC_TO_FRXUSD_SCALE);
        IUsm(FRXUSD_USM).sellAsset(usdcUsmLiquidityDrained * USDC_TO_FRXUSD_SCALE, address(this));

        require(IERC20(DUSD).balanceOf(address(this)) == dusdBefore, "DUSD balance changed during PSM route");
        require(IERC20(FRXUSD_MAINNET).balanceOf(address(this)) == 0, "frxUSD leftover after PSM route");
    }

    function _deployNewPoolLp(INonfungiblePositionManager nftMgr, uint256 deadline) internal {
        IERC20(USDC_MAINNET).forceApprove(FRAX_CUSTODIAN, collectedUsdcFromUniswapPool);
        IERC4626(FRAX_CUSTODIAN).deposit(collectedUsdcFromUniswapPool, address(this));

        newPool = nftMgr.createAndInitializePoolIfNecessary(DUSD, FRXUSD_MAINNET, POOL_FEE, uint160(Q96));

        IERC20(DUSD).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, pos1DusdCollected);
        IERC20(FRXUSD_MAINNET).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, pos1UsdcCollected * USDC_TO_FRXUSD_SCALE);
        (newPos1TokenId,, pos1DusdDeposited, pos1FrxUsdDeposited) = nftMgr.mint(
            MintParams({
                token0: DUSD,
                token1: FRXUSD_MAINNET,
                fee: POOL_FEE,
                tickLower: POS_1_LOWER,
                tickUpper: POS_1_UPPER,
                amount0Desired: pos1DusdCollected,
                amount1Desired: pos1UsdcCollected * USDC_TO_FRXUSD_SCALE,
                amount0Min: 0,
                amount1Min: 0,
                recipient: owner,
                deadline: deadline
            })
        );

        IERC20(DUSD).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, pos2DusdCollected);
        IERC20(FRXUSD_MAINNET).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, pos2UsdcCollected * USDC_TO_FRXUSD_SCALE);
        (newPos2TokenId,, pos2DusdDeposited, pos2FrxUsdDeposited) = nftMgr.mint(
            MintParams({
                token0: DUSD,
                token1: FRXUSD_MAINNET,
                fee: POOL_FEE,
                tickLower: POS_2_LOWER,
                tickUpper: POS_2_UPPER,
                amount0Desired: pos2DusdCollected,
                amount1Desired: pos2UsdcCollected * USDC_TO_FRXUSD_SCALE,
                amount0Min: 0,
                amount1Min: 0,
                recipient: owner,
                deadline: deadline
            })
        );
    }

    /// @dev Rebalance unutilized balances via frxUSD PSM, then `increaseLiquidity` on narrow pos1.
    function _sweepLeftovers(INonfungiblePositionManager nftMgr, uint256 deadline) internal {
        uint256 leftoverDusd = IERC20(DUSD).balanceOf(address(this));
        uint256 leftoverFrxUsd = IERC20(FRXUSD_MAINNET).balanceOf(address(this));

        uint256 frxUsdToSell;
        (dusdForLp, remainingFrxUsdToAddToLp, frxUsdToSell, frxUsdToBuyFromPsm) =
            _computeSweepAmounts(leftoverDusd, leftoverFrxUsd);

        frxUsdToSwapToDusd = frxUsdToSell;

        if (dusdForLp == 0 && remainingFrxUsdToAddToLp == 0) return;

        if (frxUsdToSell > 0) {
            IERC20(FRXUSD_MAINNET).forceApprove(FRXUSD_USM, frxUsdToSell);
            IUsm(FRXUSD_USM).sellAsset(frxUsdToSell, address(this));
        }

        if (frxUsdToBuyFromPsm > 0) {
            IERC20(DUSD).forceApprove(FRXUSD_USM, frxUsdToBuyFromPsm);
            IUsm(FRXUSD_USM).buyAsset(frxUsdToBuyFromPsm, address(this));
        }

        IERC20(DUSD).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, dusdForLp);
        IERC20(FRXUSD_MAINNET).forceApprove(UNISWAP_V3_NFT_POSITION_MANAGER, remainingFrxUsdToAddToLp);

        (, sweepDusdDeposited, sweepFrxUsdDeposited) = nftMgr.increaseLiquidity(
            IncreaseLiquidityParams({
                tokenId: newPos1TokenId,
                amount0Desired: dusdForLp,
                amount1Desired: remainingFrxUsdToAddToLp,
                amount0Min: 0,
                amount1Min: 0,
                deadline: deadline
            })
        );
    }

    /// @dev At 1:1 PSM, split leftovers so `dusdForLp / remainingFrxUsdToAddToLp ≈ 0.44`.
    function _computeSweepAmounts(uint256 leftoverDusd, uint256 leftoverFrxUsd)
        internal
        pure
        returns (uint256 dusdLp, uint256 frxUsdLp, uint256 frxUsdSell, uint256 frxUsdBuy)
    {
        uint256 total = leftoverDusd + leftoverFrxUsd;
        if (total < MIN_SWEEP_VALUE) return (0, 0, 0, 0);

        dusdLp = total * SWEEP_DUSD_NUM / SWEEP_SUM_DEN;
        frxUsdLp = total * SWEEP_DUSD_DEN / SWEEP_SUM_DEN;

        if (dusdLp == 0 || frxUsdLp == 0) return (0, 0, 0, 0);

        if (leftoverFrxUsd < frxUsdLp) {
            frxUsdBuy = frxUsdLp - leftoverFrxUsd;
        } else if (leftoverFrxUsd > frxUsdLp) {
            frxUsdSell = leftoverFrxUsd - frxUsdLp;
        }
    }
}
