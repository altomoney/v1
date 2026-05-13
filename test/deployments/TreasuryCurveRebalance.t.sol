// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

import {
    INonfungiblePositionManagerTreasury,
    ICurveFrxUsdDusdPool,
    DecreaseLiquidityParams,
    CollectParams,
    GenerateTreasuryCurveRebalance
} from "../../script/GenerateTreasuryCurveRebalance.s.sol";

/// @notice Fork test that executes the 15-transaction treasury Uniswap -> Curve rebalance
///         against a mainnet fork and logs balances after every step.
contract TreasuryCurveRebalanceTest is Test {
    address TREASURY;
    address BORROW_MARKET_FEE_RECIPIENT;
    address NONFUNGIBLE_POSITION_MANAGER;
    address FRAX_CUSTODIAN;
    address USDC;
    address FRXUSD;
    address DUSD;
    address FRXUSD_USM;
    address USDC_USM;
    address CONFIG_CURVE_POOL;

    uint256 NARROW_TOKEN_ID;
    uint256 WIDE_TOKEN_ID;
    uint256 BPS;
    uint256 TOKEN_DECIMAL_SCALE;
    uint256 CONFIG_NARROW_REDUCTION_BPS;
    uint256 CONFIG_NARROW_MIN_DUSD_OUT;
    uint256 CONFIG_NARROW_MIN_USDC_OUT;
    uint256 CONFIG_WIDE_REDUCTION_BPS;
    uint256 CONFIG_WIDE_MIN_DUSD_OUT;
    uint256 CONFIG_WIDE_MIN_USDC_OUT;
    uint256 CONFIG_CURVE_FRXUSD_AMOUNT;
    uint256 CONFIG_CURVE_DUSD_AMOUNT;
    uint256 CONFIG_CURVE_MIN_LP_AMOUNT;
    uint256 CONFIG_EXTRA_DUSD_TO_BURN;

    GenerateTreasuryCurveRebalance script;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        script = new GenerateTreasuryCurveRebalance();

        TREASURY = script.TREASURY();
        BORROW_MARKET_FEE_RECIPIENT = script.BORROW_MARKET_FEE_RECIPIENT();
        NONFUNGIBLE_POSITION_MANAGER = script.NONFUNGIBLE_POSITION_MANAGER();
        FRAX_CUSTODIAN = script.FRAX_CUSTODIAN();
        USDC = script.USDC();
        FRXUSD = script.FRXUSD();
        DUSD = script.DUSD();
        FRXUSD_USM = script.FRXUSD_USM();
        USDC_USM = script.USDC_USM();
        CONFIG_CURVE_POOL = script.CONFIG_CURVE_POOL();

        NARROW_TOKEN_ID = script.NARROW_TOKEN_ID();
        WIDE_TOKEN_ID = script.WIDE_TOKEN_ID();
        BPS = script.BPS();
        TOKEN_DECIMAL_SCALE = script.TOKEN_DECIMAL_SCALE();
        CONFIG_NARROW_REDUCTION_BPS = script.CONFIG_NARROW_REDUCTION_BPS();
        CONFIG_NARROW_MIN_DUSD_OUT = script.CONFIG_NARROW_MIN_DUSD_OUT();
        CONFIG_NARROW_MIN_USDC_OUT = script.CONFIG_NARROW_MIN_USDC_OUT();
        CONFIG_WIDE_REDUCTION_BPS = script.CONFIG_WIDE_REDUCTION_BPS();
        CONFIG_WIDE_MIN_DUSD_OUT = script.CONFIG_WIDE_MIN_DUSD_OUT();
        CONFIG_WIDE_MIN_USDC_OUT = script.CONFIG_WIDE_MIN_USDC_OUT();
        CONFIG_CURVE_FRXUSD_AMOUNT = script.CONFIG_CURVE_FRXUSD_AMOUNT();
        CONFIG_CURVE_DUSD_AMOUNT = script.CONFIG_CURVE_DUSD_AMOUNT();
        CONFIG_CURVE_MIN_LP_AMOUNT = script.CONFIG_CURVE_MIN_LP_AMOUNT();
        CONFIG_EXTRA_DUSD_TO_BURN = script.CONFIG_EXTRA_DUSD_TO_BURN();
    }

    function test_TreasuryCurveRebalance() public {
        _logHeader("INITIAL STATE");
        _logTreasuryBalances();
        _logUniswapPosition("narrow", NARROW_TOKEN_ID);
        _logUniswapPosition("wide", WIDE_TOKEN_ID);
        _logCurvePool();

        uint256 deadline = block.timestamp + 36 hours;

        // ── TX 1: transfer existing DUSD to fee recipient ─────────────────────
        uint256 initialDusd = IERC20(DUSD).balanceOf(TREASURY);
        vm.startPrank(TREASURY);
        IERC20(DUSD).transfer(BORROW_MARKET_FEE_RECIPIENT, initialDusd);
        _logHeader("Post TX 1: transfer existing DUSD to borrow market fee recipient");
        _logTreasuryBalances();
        console.log("  Fee recipient DUSD: %s", vm.toString(IERC20(DUSD).balanceOf(BORROW_MARKET_FEE_RECIPIENT)));

        // ── TX 2: decreaseLiquidity narrow ────────────────────────────────────
        {
            (,,,,,,, uint128 liq,,,,) = _positions(NARROW_TOKEN_ID);
            uint128 toRemove = uint128(uint256(liq) * CONFIG_NARROW_REDUCTION_BPS / BPS);

            INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER)
                .decreaseLiquidity(
                    DecreaseLiquidityParams({
                        tokenId: NARROW_TOKEN_ID,
                        liquidity: toRemove,
                        amount0Min: CONFIG_NARROW_MIN_DUSD_OUT,
                        amount1Min: CONFIG_NARROW_MIN_USDC_OUT,
                        deadline: deadline
                    })
                );
        }
        _logHeader("Post TX 2: decreaseLiquidity from uniswap narrow range position");
        _logTreasuryBalances();
        _logUniswapPosition("narrow", NARROW_TOKEN_ID);

        // ── TX 3: collect narrow ──────────────────────────────────────────────
        INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER)
            .collect(
                CollectParams({
                    tokenId: NARROW_TOKEN_ID,
                    recipient: TREASURY,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        _logHeader("Post TX 3: collect from uniswap narrow range position");
        _logTreasuryBalances();

        // ── TX 4: decreaseLiquidity wide ──────────────────────────────────────
        {
            (,,,,,,, uint128 liq,,,,) = _positions(WIDE_TOKEN_ID);
            uint128 toRemove = uint128(uint256(liq) * CONFIG_WIDE_REDUCTION_BPS / BPS);

            INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER)
                .decreaseLiquidity(
                    DecreaseLiquidityParams({
                        tokenId: WIDE_TOKEN_ID,
                        liquidity: toRemove,
                        amount0Min: CONFIG_WIDE_MIN_DUSD_OUT,
                        amount1Min: CONFIG_WIDE_MIN_USDC_OUT,
                        deadline: deadline
                    })
                );
        }
        _logHeader("Post TX 4: decreaseLiquidity from uniswap wide range position");
        _logTreasuryBalances();
        _logUniswapPosition("wide", WIDE_TOKEN_ID);

        // ── TX 5: collect wide ────────────────────────────────────────────────
        INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER)
            .collect(
                CollectParams({
                    tokenId: WIDE_TOKEN_ID,
                    recipient: TREASURY,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

        _logHeader("Post TX 5: collect from uniswap wide range position");
        _logTreasuryBalances();

        uint256 usdcForCurveDusd = CONFIG_CURVE_DUSD_AMOUNT / TOKEN_DECIMAL_SCALE;
        uint256 usdcForCurveFrxUsd = CONFIG_CURVE_FRXUSD_AMOUNT / TOKEN_DECIMAL_SCALE;
        uint256 totalUsdcForFrax = usdcForCurveDusd + usdcForCurveFrxUsd;

        // ── TX 6: approve USDC to fraxCustodian ───────────────────────────────
        IERC20(USDC).approve(FRAX_CUSTODIAN, totalUsdcForFrax);

        _logHeader("Post TX 6: approve USDC to fraxCustodian to get frxUSD and then mint DUSD from frxUSD USM");
        _logTreasuryBalances();

        // ── TX 7: fraxCustodian.deposit for DUSD leg ──────────────────────────
        IERC4626(FRAX_CUSTODIAN).deposit(usdcForCurveDusd, TREASURY);
        _logHeader("Post TX 7: fraxCustodian.deposit USDC to get frxUSD and then mint DUSD from frxUSD USM");
        _logTreasuryBalances();

        // ── TX 8: approve frxUSD to FRXUSD_USM ───────────────────────────────
        IERC20(FRXUSD).approve(FRXUSD_USM, CONFIG_CURVE_DUSD_AMOUNT);

        _logHeader("Post TX 8: approve frxUSD to frxUSD USM to mint DUSD to deposit to Curve pool");
        _logTreasuryBalances();

        // ── TX 9: sellAsset frxUSD for DUSD ──────────────────────────────────
        IUsm(FRXUSD_USM).sellAsset(CONFIG_CURVE_DUSD_AMOUNT, TREASURY);
        _logHeader("Post TX 9: frxUSD USM sellAsset to get DUSD to deposit to Curve pool");
        _logTreasuryBalances();

        // ── TX 10: fraxCustodian.deposit for frxUSD leg ──────────────────────
        IERC4626(FRAX_CUSTODIAN).deposit(CONFIG_CURVE_FRXUSD_AMOUNT / TOKEN_DECIMAL_SCALE, TREASURY);
        _logHeader("Post TX 10: fraxCustodian.deposit USDC to get frxUSD to deposit to Curve pool");
        _logTreasuryBalances();

        // ── TX 11: approve frxUSD to Curve ───────────────────────────────────
        IERC20(FRXUSD).approve(CONFIG_CURVE_POOL, CONFIG_CURVE_FRXUSD_AMOUNT);

        _logHeader("Post TX 11: approve frxUSD to Curve");
        _logTreasuryBalances();

        // ── TX 12: approve DUSD to Curve ─────────────────────────────────────
        IERC20(DUSD).approve(CONFIG_CURVE_POOL, CONFIG_CURVE_DUSD_AMOUNT);

        _logHeader("Post TX 12: approve DUSD to Curve");
        _logTreasuryBalances();

        // ── TX 13: Curve add_liquidity ────────────────────────────────────────
        {
            address coin0 = ICurveFrxUsdDusdPool(CONFIG_CURVE_POOL).coins(0);
            uint256[] memory amounts = new uint256[](2);
            if (coin0 == FRXUSD) {
                amounts[0] = CONFIG_CURVE_FRXUSD_AMOUNT;
                amounts[1] = CONFIG_CURVE_DUSD_AMOUNT;
            } else {
                amounts[0] = CONFIG_CURVE_DUSD_AMOUNT;
                amounts[1] = CONFIG_CURVE_FRXUSD_AMOUNT;
            }
            uint256 lpMinted =
                ICurveFrxUsdDusdPool(CONFIG_CURVE_POOL).add_liquidity(amounts, CONFIG_CURVE_MIN_LP_AMOUNT, TREASURY);

            console.log("  LP tokens minted: %s", vm.toString(lpMinted));
            assertGe(lpMinted, CONFIG_CURVE_MIN_LP_AMOUNT, "LP minted below configured minimum");
        }
        _logHeader("Post TX 13: Curve add_liquidity to get LP tokens");
        _logTreasuryBalances();
        _logCurvePool();

        // ── TX 14: approve extra DUSD to USDC_USM ────────────────────────────
        IERC20(DUSD).approve(USDC_USM, CONFIG_EXTRA_DUSD_TO_BURN);

        _logHeader("Post TX 14: approve extra DUSD to USDC USM to buy USDC");
        _logTreasuryBalances();

        // ── TX 15: buyAsset extra DUSD -> USDC ───────────────────────────────
        IUsm(USDC_USM).buyAsset(CONFIG_EXTRA_DUSD_TO_BURN / TOKEN_DECIMAL_SCALE, TREASURY);

        vm.stopPrank();
        _logHeader("Post TX 15: USDC USM buyAsset extra DUSD to get USDC");
        _logTreasuryBalances();

        _logHeader("FINAL STATE");
        _logUniswapPosition("narrow", NARROW_TOKEN_ID);
        _logUniswapPosition("wide", WIDE_TOKEN_ID);
        _logCurvePool();

        _assertFinalState();
    }

    function _assertFinalState() internal view {
        (,,,,,,, uint128 narrowLiq,,,,) = _positions(NARROW_TOKEN_ID);
        (,,,,,,, uint128 wideLiq,,,,) = _positions(WIDE_TOKEN_ID);

        uint256 narrowOriginal = 2368915007018330610639;
        uint256 wideOriginal = 15860032301389520788;
        uint256 narrowExpectedRemaining = narrowOriginal - (narrowOriginal * CONFIG_NARROW_REDUCTION_BPS / BPS);
        uint256 wideExpectedRemaining = wideOriginal - (wideOriginal * CONFIG_WIDE_REDUCTION_BPS / BPS);
        assertEq(uint256(narrowLiq), narrowExpectedRemaining, "narrow remaining liquidity mismatch");
        assertEq(uint256(wideLiq), wideExpectedRemaining, "wide remaining liquidity mismatch");

        uint256 curvePoolDusd = IERC20(DUSD).balanceOf(CONFIG_CURVE_POOL);
        uint256 curvePoolFrxUsd = IERC20(FRXUSD).balanceOf(CONFIG_CURVE_POOL);
        assertGe(curvePoolDusd, CONFIG_CURVE_DUSD_AMOUNT, "Curve pool DUSD below deposit amount");
        assertGe(curvePoolFrxUsd, CONFIG_CURVE_FRXUSD_AMOUNT, "Curve pool frxUSD below deposit amount");

        uint256 treasuryFrxUsd = IERC20(FRXUSD).balanceOf(TREASURY);
        assertEq(treasuryFrxUsd, 0, "treasury should have no leftover frxUSD");

        uint256 treasuryDusd = IERC20(DUSD).balanceOf(TREASURY);
        assertLe(treasuryDusd, 10_000 ether, "excessive DUSD left unconverted in treasury");
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    function _logHeader(string memory label) internal pure {
        console.log("\n==========================================");
        console.log("  %s", label);
        console.log("==========================================");
    }

    function _logTreasuryBalances() internal view {
        console.log("  Treasury USDC  : %s", vm.toString(IERC20(USDC).balanceOf(TREASURY)));
        console.log("  Treasury DUSD  : %s", vm.toString(IERC20(DUSD).balanceOf(TREASURY)));
        console.log("  Treasury frxUSD: %s", vm.toString(IERC20(FRXUSD).balanceOf(TREASURY)));
    }

    function _logUniswapPosition(string memory label, uint256 tokenId) internal view {
        (,,,,,,, uint128 liq,,, uint128 owed0, uint128 owed1) = _positions(tokenId);
        console.log("  [uni %s] liquidity=%s  tokensOwed0(DUSD)=%s", label, vm.toString(liq), vm.toString(owed0));
        console.log("  [uni %s] tokensOwed1(USDC)=%s", label, vm.toString(owed1));
    }

    function _logCurvePool() internal view {
        console.log("  Curve pool DUSD  : %s", vm.toString(IERC20(DUSD).balanceOf(CONFIG_CURVE_POOL)));
        console.log("  Curve pool frxUSD: %s", vm.toString(IERC20(FRXUSD).balanceOf(CONFIG_CURVE_POOL)));
    }

    function _positions(uint256 tokenId)
        internal
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
        )
    {
        return INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER).positions(tokenId);
    }
}
