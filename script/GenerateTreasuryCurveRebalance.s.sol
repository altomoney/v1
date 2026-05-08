// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
}

struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
}

interface INonfungiblePositionManagerTreasury {
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface ICurveFrxUsdDusdPool {
    function coins(uint256 i) external view returns (address);

    function calc_token_amount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);
}

/// @title GenerateTreasuryCurveRebalance
/// @notice Generates Safe Transaction Builder JSON for the treasury Uniswap -> Curve rebalance.
/// @dev command to run: forge script script/GenerateTreasuryCurveRebalance.s.sol:GenerateTreasuryCurveRebalance  --rpc-url ethereum
contract GenerateTreasuryCurveRebalance is Script {
    struct PositionConfig {
        string label;
        uint256 tokenId;
        uint256 reductionBps;
        uint256 minDusdOut;
        uint256 minUsdcOut;
    }

    struct CurveConfig {
        uint256 frxUsdAmount;
        uint256 dusdAmount;
    }

    struct PositionState {
        uint128 currentLiquidity;
        uint128 liquidityToRemove;
    }

    struct BuildContext {
        PositionConfig narrow;
        PositionConfig wide;
        CurveConfig curveConfig;
        PositionState narrowState;
        PositionState wideState;
        uint256[] curveAmounts;
        uint256 curveMinMintAmount;
        uint256 totalUsdcForFrax;
        uint256 extraDusd;
        address[] to;
        bytes[] data;
        string[] labels;
    }

    address public constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address public constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address public constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;

    uint256 public constant NARROW_TOKEN_ID = 1_150_307;
    uint256 public constant WIDE_TOKEN_ID = 1_150_308;
    uint256 public constant BPS = 10_000;
    uint256 public constant TOKEN_DECIMAL_SCALE = 1e12; // 18-decimal frxUSD/DUSD to 6-decimal USDC.

    // Update to the target Curve frxUSD/DUSD pool.
    address public constant CONFIG_CURVE_POOL = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    // Update to set the Uniswap decreaseLiquidity deadline relative to script execution.
    uint256 public constant CONFIG_DEADLINE_HOURS = 36;

    // Narrow position: update bps and minimum received token amounts before generating Safe calldata.
    uint256 public constant CONFIG_NARROW_REDUCTION_BPS = 3_400;
    uint256 public constant CONFIG_NARROW_MIN_DUSD_OUT = 98_600 ether;
    uint256 public constant CONFIG_NARROW_MIN_USDC_OUT = 299_200 * 1e6;

    // Wide position: update bps and minimum received token amounts before generating Safe calldata.
    uint256 public constant CONFIG_WIDE_REDUCTION_BPS = 3_400;
    uint256 public constant CONFIG_WIDE_MIN_DUSD_OUT = 16_666 ether;
    uint256 public constant CONFIG_WIDE_MIN_USDC_OUT = 78_200 * 1e6;

    // Update to the desired Curve deposit amounts. Curve coin order is read from the pool.
    uint256 public constant CONFIG_CURVE_FRXUSD_AMOUNT = 250_000 ether;
    uint256 public constant CONFIG_CURVE_DUSD_AMOUNT = 250_000 ether;
    // Minimum Curve LP tokens to accept from add_liquidity (slippage guard). Run calc_token_amount off-chain to set this.
    uint256 public constant CONFIG_CURVE_MIN_LP_AMOUNT = 490_000 ether;

    // DUSD actually received from Uniswap positions to burn back via USDC USM.
    // May exceed the sum of minDusdOut values if the pool price moved favourably.
    uint256 public constant CONFIG_EXTRA_DUSD_TO_BURN = 115_266 ether;

    string public constant OUTPUT_FILE =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-treasury-curve-rebalance.json";

    function run() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        address curvePool = CONFIG_CURVE_POOL;
        require(curvePool.code.length > 0, "Invalid curve pool address");

        address curveCoin0 = ICurveFrxUsdDusdPool(curvePool).coins(0);
        address curveCoin1 = ICurveFrxUsdDusdPool(curvePool).coins(1);
        require(
            (curveCoin0 == FRXUSD && curveCoin1 == DUSD) || (curveCoin0 == DUSD && curveCoin1 == FRXUSD),
            "curve pool coins[0,1] must be frxUSD and DUSD"
        );

        uint256 deadline = block.timestamp + CONFIG_DEADLINE_HOURS * 1 hours;

        _buildAndWrite(curvePool, curveCoin0, deadline);
    }

    function _buildAndWrite(address curvePool, address curveCoin0, uint256 deadline) internal {
        BuildContext memory ctx;
        ctx.narrow = PositionConfig({
            label: "narrow tick range",
            tokenId: NARROW_TOKEN_ID,
            reductionBps: CONFIG_NARROW_REDUCTION_BPS,
            minDusdOut: CONFIG_NARROW_MIN_DUSD_OUT,
            minUsdcOut: CONFIG_NARROW_MIN_USDC_OUT
        });
        require(ctx.narrow.reductionBps <= BPS, "narrow reduction bps too high");
        ctx.wide = PositionConfig({
            label: "wide tick range",
            tokenId: WIDE_TOKEN_ID,
            reductionBps: CONFIG_WIDE_REDUCTION_BPS,
            minDusdOut: CONFIG_WIDE_MIN_DUSD_OUT,
            minUsdcOut: CONFIG_WIDE_MIN_USDC_OUT
        });
        require(ctx.wide.reductionBps <= BPS, "wide reduction bps too high");
        ctx.curveConfig = CurveConfig({frxUsdAmount: CONFIG_CURVE_FRXUSD_AMOUNT, dusdAmount: CONFIG_CURVE_DUSD_AMOUNT});
        ctx.narrowState = _positionState(ctx.narrow);
        ctx.wideState = _positionState(ctx.wide);
        ctx.curveAmounts = new uint256[](2);
        if (curveCoin0 == FRXUSD) {
            ctx.curveAmounts[0] = ctx.curveConfig.frxUsdAmount;
            ctx.curveAmounts[1] = ctx.curveConfig.dusdAmount;
        } else {
            ctx.curveAmounts[0] = ctx.curveConfig.dusdAmount;
            ctx.curveAmounts[1] = ctx.curveConfig.frxUsdAmount;
        }
        uint256 expectedLp = ICurveFrxUsdDusdPool(curvePool).calc_token_amount(ctx.curveAmounts, true);
        console.log("Expected Curve LP from calc_token_amount: %s", vm.toString(expectedLp));
        console.log("Configured Curve min LP (CONFIG_CURVE_MIN_LP_AMOUNT): %s", vm.toString(CONFIG_CURVE_MIN_LP_AMOUNT));
        ctx.curveMinMintAmount = CONFIG_CURVE_MIN_LP_AMOUNT;
        ctx.extraDusd = CONFIG_EXTRA_DUSD_TO_BURN;
        ctx.to = new address[](14);
        ctx.data = new bytes[](14);
        ctx.labels = new string[](14);

        _printStateBefore(curvePool, ctx);

        uint256 idx;

        _appendDecreaseLiquidity(ctx, idx++, true, deadline);
        _appendCollect(ctx, idx++, true);
        _appendDecreaseLiquidity(ctx, idx++, false, deadline);
        _appendCollect(ctx, idx++, false);

        uint256 usdcForCurveDusd = ctx.curveConfig.dusdAmount / TOKEN_DECIMAL_SCALE;
        uint256 usdcForCurveFrxUsd = ctx.curveConfig.frxUsdAmount / TOKEN_DECIMAL_SCALE;
        ctx.totalUsdcForFrax = usdcForCurveDusd + usdcForCurveFrxUsd;

        ctx.labels[idx] = "approve USDC to fraxCustodian to get frxUSD and then mint DUSD from frxUSD USM";
        ctx.to[idx] = USDC;
        ctx.data[idx] = abi.encodeCall(IERC20.approve, (FRAX_CUSTODIAN, ctx.totalUsdcForFrax));
        ++idx;

        ctx.labels[idx] = "fraxCustodian.deposit USDC to get frxUSD and then mint DUSD from frxUSD USM";
        ctx.to[idx] = FRAX_CUSTODIAN;
        ctx.data[idx] = abi.encodeCall(IERC4626.deposit, (usdcForCurveDusd, TREASURY));
        ++idx;

        ctx.labels[idx] = "approve frxUSD to frxUSD USM to mint DUSD to deposit to Curve pool";
        ctx.to[idx] = FRXUSD;
        ctx.data[idx] = abi.encodeCall(IERC20.approve, (FRXUSD_USM, ctx.curveConfig.dusdAmount));
        ++idx;

        ctx.labels[idx] = "frxUSD USM sellAsset to get DUSD to deposit to Curve pool";
        ctx.to[idx] = FRXUSD_USM;
        ctx.data[idx] = abi.encodeCall(IUsm.sellAsset, (ctx.curveConfig.dusdAmount, TREASURY));
        ++idx;

        ctx.labels[idx] = "fraxCustodian.deposit USDC to get frxUSD to deposit to Curve pool";
        ctx.to[idx] = FRAX_CUSTODIAN;
        ctx.data[idx] = abi.encodeCall(IERC4626.deposit, (usdcForCurveFrxUsd, TREASURY));
        ++idx;

        ctx.labels[idx] = "approve frxUSD to Curve to deposit to Curve pool";
        ctx.to[idx] = FRXUSD;
        ctx.data[idx] = abi.encodeCall(IERC20.approve, (curvePool, ctx.curveConfig.frxUsdAmount));
        ++idx;

        ctx.labels[idx] = "approve DUSD to Curve to deposit to Curve pool";
        ctx.to[idx] = DUSD;
        ctx.data[idx] = abi.encodeCall(IERC20.approve, (curvePool, ctx.curveConfig.dusdAmount));
        ++idx;

        ctx.labels[idx] = "Curve add_liquidity to get LP tokens";
        ctx.to[idx] = curvePool;
        ctx.data[idx] =
            abi.encodeCall(ICurveFrxUsdDusdPool.add_liquidity, (ctx.curveAmounts, ctx.curveMinMintAmount, TREASURY));
        ++idx;

        ctx.labels[idx] = "approve extra DUSD received from uniswap positions to USDC USM to buy USDC";
        ctx.to[idx] = DUSD;
        ctx.data[idx] = abi.encodeCall(IERC20.approve, (USDC_USM, ctx.extraDusd));
        ++idx;

        ctx.labels[idx] = "USDC USM buyAsset to get USDC";
        ctx.to[idx] = USDC_USM;
        ctx.data[idx] = abi.encodeCall(IUsm.buyAsset, (ctx.extraDusd / TOKEN_DECIMAL_SCALE, TREASURY));
        ++idx;

        require(idx == ctx.to.length, "transaction count mismatch");

        _printStateAfter(curvePool, ctx);
        _logTransactions(ctx.labels, ctx.to, ctx.data);
        _writeSafeBatch(ctx.to, ctx.data);
    }

    function _positionState(PositionConfig memory cfg) internal view returns (PositionState memory state) {
        (address token0, address token1, uint128 liq) = _positionInfo(cfg.tokenId);
        require(token0 == DUSD, "unexpected Uniswap token0");
        require(token1 == USDC, "unexpected Uniswap token1");
        state.currentLiquidity = liq;

        state.liquidityToRemove = uint128(uint256(state.currentLiquidity) * cfg.reductionBps / BPS);
        require(state.liquidityToRemove > 0, "zero liquidity to remove");
    }

    function _appendDecreaseLiquidity(BuildContext memory ctx, uint256 idx, bool isNarrow, uint256 deadline)
        internal
        pure
    {
        PositionConfig memory cfg = isNarrow ? ctx.narrow : ctx.wide;
        PositionState memory state = isNarrow ? ctx.narrowState : ctx.wideState;
        DecreaseLiquidityParams memory params = DecreaseLiquidityParams({
            tokenId: cfg.tokenId,
            liquidity: state.liquidityToRemove,
            amount0Min: cfg.minDusdOut,
            amount1Min: cfg.minUsdcOut,
            deadline: deadline
        });

        ctx.labels[idx] = string.concat("Uniswap decreaseLiquidity from uniswap position ", cfg.label);
        ctx.to[idx] = NONFUNGIBLE_POSITION_MANAGER;
        ctx.data[idx] = abi.encodeCall(INonfungiblePositionManagerTreasury.decreaseLiquidity, (params));
    }

    function _appendCollect(BuildContext memory ctx, uint256 idx, bool isNarrow) internal pure {
        PositionConfig memory cfg = isNarrow ? ctx.narrow : ctx.wide;
        CollectParams memory params = CollectParams({
            tokenId: cfg.tokenId, recipient: TREASURY, amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        ctx.labels[idx] = string.concat("Uniswap collect ", cfg.label);
        ctx.to[idx] = NONFUNGIBLE_POSITION_MANAGER;
        ctx.data[idx] = abi.encodeCall(INonfungiblePositionManagerTreasury.collect, (params));
    }

    function _positionInfo(uint256 tokenId) internal view returns (address token0, address token1, uint128 liquidity) {
        (,, token0, token1,,,, liquidity,,,,) =
            INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER).positions(tokenId);
    }

    function _printStateBefore(address curvePool, BuildContext memory ctx) internal view {
        console.log("\n=== State Before ===");
        _printBalances("Treasury", TREASURY);
        _printBalances("Curve pool", curvePool);
        _printPositionState("narrow", ctx.narrow, ctx.narrowState);
        _printPositionState("wide", ctx.wide, ctx.wideState);
    }

    function _printStateAfter(address curvePool, BuildContext memory ctx) internal view {
        uint256 projectedUsdc = IERC20(USDC).balanceOf(TREASURY) - ctx.totalUsdcForFrax + ctx.narrow.minUsdcOut
            + ctx.wide.minUsdcOut + ctx.extraDusd / TOKEN_DECIMAL_SCALE;
        uint256 projectedDusd = IERC20(DUSD).balanceOf(TREASURY);
        uint256 projectedFrxUsd = IERC20(FRXUSD).balanceOf(TREASURY);

        console.log("\n=== Projected State After (using configured mins) ===");
        _printTokenAmounts("Treasury", projectedUsdc, projectedDusd, projectedFrxUsd);
        _printTokenAmounts(
            "Curve pool",
            IERC20(USDC).balanceOf(curvePool),
            IERC20(DUSD).balanceOf(curvePool) + ctx.curveConfig.dusdAmount,
            IERC20(FRXUSD).balanceOf(curvePool) + ctx.curveConfig.frxUsdAmount
        );
        _printPositionAfter("narrow", ctx.narrow, ctx.narrowState);
        _printPositionAfter("wide", ctx.wide, ctx.wideState);
    }

    function _printBalances(string memory label, address account) internal view {
        _printTokenAmounts(
            label, IERC20(USDC).balanceOf(account), IERC20(DUSD).balanceOf(account), IERC20(FRXUSD).balanceOf(account)
        );
    }

    function _printTokenAmounts(string memory label, uint256 usdcAmount, uint256 dusdAmount, uint256 frxUsdAmount)
        internal
        view
    {
        console.log("%s balances:", label);
        console.log("  USDC  : %s", vm.toString(usdcAmount));
        console.log("  DUSD  : %s", vm.toString(dusdAmount));
        console.log("  frxUSD: %s", vm.toString(frxUsdAmount));
    }

    function _printPositionState(string memory label, PositionConfig memory cfg, PositionState memory state)
        internal
        view
    {
        console.log("%s Uniswap position:", label);
        console.log("  current liquidity : %s", vm.toString(state.currentLiquidity));
        console.log("  remove liquidity  : %s", vm.toString(state.liquidityToRemove));
        console.log("  configured DUSD min : %s", vm.toString(cfg.minDusdOut));
        console.log("  configured USDC min : %s", vm.toString(cfg.minUsdcOut));
    }

    function _printPositionAfter(string memory label, PositionConfig memory cfg, PositionState memory state)
        internal
        view
    {
        console.log("%s Uniswap position after:", label);
        console.log("  remaining liquidity: %s", vm.toString(state.currentLiquidity - state.liquidityToRemove));
        console.log("  min DUSD removed   : %s", vm.toString(cfg.minDusdOut));
        console.log("  min USDC removed   : %s", vm.toString(cfg.minUsdcOut));
    }

    function _logTransactions(string[] memory labels, address[] memory to, bytes[] memory data) internal view {
        console.log("=== Treasury Curve Rebalance - %s transactions ===", vm.toString(to.length));
        for (uint256 i; i < to.length; ++i) {
            console.log("TX %s: %s", vm.toString(i + 1), labels[i]);
            console.log("     to   : %s", to[i]);
            console.log("     value: 0");
            console.log("     data : %s", vm.toString(data[i]));
        }
    }

    function _writeSafeBatch(address[] memory to, bytes[] memory data) internal {
        string memory txList;
        for (uint256 i; i < to.length; ++i) {
            string memory entry =
                string.concat('{"to":"', vm.toString(to[i]), '","value":"0","data":"', vm.toString(data[i]), '"}');
            txList = i == 0 ? entry : string.concat(txList, ",", entry);
        }

        string memory json = string.concat(
            '{"version":"1.0","chainId":"1",',
            '"meta":{"name":"Treasury Curve Rebalance"},',
            '"transactions":[',
            txList,
            "]}"
        );

        vm.writeFile(OUTPUT_FILE, json);
        console.log("\nSafe TX JSON written to: %s", OUTPUT_FILE);
    }
}
