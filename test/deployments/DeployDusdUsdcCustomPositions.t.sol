// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    DeployAltoEthereumMainnet,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeploymentPhase
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {USDC_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @title Custom DUSD/USDC Uniswap V3 Position Deployment Test
/// @notice Tests deploying specific LP positions with custom ranges and asymmetric amounts
contract DeployDusdUsdcCustomPositionsTest is Test {
    address constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    uint24 constant FEE_100 = 100; // 0.01%
    int24 constant TICK_SPACING = 1;

    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    address DEPLOYER;
    INonfungiblePositionManager nftManager;
    DUSD dusd;
    IERC20 usdc;

    // Token ordering (set in setUp)
    address token0;
    address token1;
    bool dusdIsToken0;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 23932561);
        DEPLOYER = address(this);

        nftManager = INonfungiblePositionManager(UNISWAP_V3_NFT_POSITION_MANAGER);
        usdc = IERC20(USDC_MAINNET);

        // Deploy DUSD
        params = AltoEthereumMainnetParams({
            timelockAdmin: makeAddr("TIMELOCK_ADMIN"),
            timelockDelay: 2 days,
            freezer: makeAddr("FREEZER_PAUSER"),
            deployer: DEPLOYER,
            phase: DeploymentPhase.CORE,
            useUnsafeUpgrades: true,
            treasuryMultisig: address(1)
        });

        input = DeployAltoEthereumMainnet.deploy(params, input);
        params.phase = DeploymentPhase.DUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        dusd = DUSD(input.contracts.dusd);

        // Determine token ordering
        dusdIsToken0 = address(dusd) < address(usdc);
        token0 = dusdIsToken0 ? address(dusd) : address(usdc);
        token1 = dusdIsToken0 ? address(usdc) : address(dusd);
    }

    /// @notice Convert a price ratio to tick offset
    /// @param priceRatio The price ratio scaled by precision (e.g., 999 with precision 1000 = 0.999)
    /// @param precision The scaling factor (e.g., 1000 or 10000)
    /// @dev tick_offset = log(priceRatio/precision) / log(1.0001)
    function _priceToTickOffset(uint256 priceRatio, uint256 precision) internal pure returns (int24) {
        // priceRatio is scaled by precision (e.g., 999 with precision 1000 = 0.999)
        // log(priceRatio/precision) / log(1.0001)
        // For small deviations: log(1+x) ≈ x, and log(1.0001) ≈ 0.0001
        // So tick_offset ≈ (priceRatio - precision) / precision / 0.0001
        //                 = (priceRatio - precision) * 10000 / precision

        if (priceRatio >= precision) {
            return int24(int256((priceRatio - precision) * 10000 / precision));
        } else {
            return -int24(int256((precision - priceRatio) * 10000 / precision));
        }
    }

    /// @notice Get tick bounds for a price range
    /// @param priceLow Lower bound (e.g., 999 for 0.999, precision 1000)
    /// @param priceHigh Upper bound (e.g., 1001 for 1.001, precision 1000)
    /// @param baseTick The tick at 1:1 price
    function _getTicksForPriceRange(uint256 priceLow, uint256 priceHigh, uint256 precision, int24 baseTick)
        internal
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        int24 offsetLow = _priceToTickOffset(priceLow, precision);
        int24 offsetHigh = _priceToTickOffset(priceHigh, precision);

        tickLower = baseTick + offsetLow;
        tickUpper = baseTick + offsetHigh;

        // Ensure ordering
        if (tickLower > tickUpper) {
            (tickLower, tickUpper) = (tickUpper, tickLower);
        }
    }

    /// @notice Test with exact tick values for precision
    /// @dev IMPORTANT: Uniswap V3 determines deposit ratios based on tick range & current price
    /// We of course cannot arbitrarily choose amounts - the protocol calculates what's needed
    function test_customPositions_exactTicks() public {
        uint160 sqrtPriceX96 = _getSqrtPriceX96ForOneToOne();
        address poolAddr = nftManager.createAndInitializePoolIfNecessary(token0, token1, FEE_100, sqrtPriceX96);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);

        (, int24 baseTick,,,,,) = pool.slot0();

        console.log("=== EXACT TICK CALCULATION ===");
        console.log("Base tick at 1:1 price:", baseTick);
        console.log("sqrtPriceX96 of pool:", sqrtPriceX96);

        // Tick math for price ranges:
        // tick_offset = log(price_ratio) / log(1.0001)
        // 0.9993  -> -7 ticks
        // 1.0003 -> +3 ticks
        // 0.97   -> -304 ticks
        // 1.007  -> +70 ticks

        // Position 1: 0.9993 - 1.0003 (tight, 10 ticks)
        int24 pos1Lower = baseTick - 7; // 0.9993
        int24 pos1Upper = baseTick + 3; // 1.0003

        // Position 2: 0.97 - 1.007 (wide, 600 ticks)
        int24 pos2Lower = baseTick - 304;
        int24 pos2Upper = baseTick + 70;

        console.log("Position 1 ticks (0.9993 - 1.0003):");
        console.logInt(pos1Lower);
        console.logInt(pos1Upper);

        console.log("Position 2 ticks (0.97 - 1.007):");
        console.logInt(pos2Lower);
        console.logInt(pos2Upper);

        _mintTokens();
        dusd.approve(UNISWAP_V3_NFT_POSITION_MANAGER, 300_000 ether);
        usdc.approve(UNISWAP_V3_NFT_POSITION_MANAGER, 1_200_000 * 1e6);

        // Position 1
        console.log("=== POSITION 1: Tight Range ===");
        console.log("Requested: 240,000 DUSD + 960,000 USDC");
        (uint256 id1, uint128 liq1, uint256 a0_1, uint256 a1_1) =
            _mintPosition(pos1Lower, pos1Upper, 240_000 ether, 960_000 * 1e6);

        console.log("NFT ID:", id1);
        console.log("Liquidity:", liq1);
        console.log("ACTUALLY deposited:");
        _logActualDeposit(a0_1, a1_1);

        // Position 2
        console.log("=== POSITION 2: Wide Range ===");
        console.log("Requested: 60,000 DUSD + 240,000 USDC");
        (uint256 id2, uint128 liq2, uint256 a0_2, uint256 a1_2) =
            _mintPosition(pos2Lower, pos2Upper, 60_000 ether, 240_000 * 1e6);

        console.log("NFT ID:", id2);
        console.log("Liquidity:", liq2);
        console.log("ACTUALLY deposited:");
        _logActualDeposit(a0_2, a1_2);

        console.log("=== FINAL STATE ===");
        console.log("Pool liquidity:", pool.liquidity());

        assertGt(liq1, 0);
        assertGt(liq2, 0);

        // Verify trading at ~1:1
        console.log("=== SWAP VERIFICATION ===");
        _verifySwapRate(pool);
    }

    /// @notice Verify the pool trades at approximately 1:1
    function _verifySwapRate(IUniswapV3Pool pool) internal {
        // Create a swapper with some USDC
        address swapper = makeAddr("swapper");
        uint256 swapAmount = 1000 * 1e6; // 1000 USDC

        deal(address(usdc), swapper, swapAmount);

        // Determine swap direction: USDC -> DUSD
        bool zeroForOne = !dusdIsToken0; // If DUSD is token0, we swap token1 (USDC) for token0

        // Create swap helper
        SwapHelper helper = new SwapHelper(pool);

        vm.startPrank(swapper);
        usdc.transfer(address(helper), swapAmount);
        vm.stopPrank();

        uint256 dusdBefore = dusd.balanceOf(swapper);
        helper.swap(zeroForOne, int256(swapAmount), swapper);
        uint256 dusdAfter = dusd.balanceOf(swapper);

        uint256 dusdReceived = dusdAfter - dusdBefore;

        // Calculate effective rate: how many DUSD per 1 USDC
        // 1000 USDC (1e9 raw) should give ~1000 DUSD (1e21 raw)
        // Rate = dusdReceived / swapAmount * 1e6 (to normalize decimals)
        uint256 rateScaled = (dusdReceived * 1e6) / swapAmount; // Should be ~1e18 for 1:1

        console.log("Swapped: 1000 USDC");
        console.log("Received DUSD (raw):", dusdReceived);
        console.log("Received DUSD:", dusdReceived / 1e18);
        console.log("Rate (DUSD per USDC, scaled 1e18):", rateScaled);

        // Check rate is within 1% of 1:1
        // 1e18 = exactly 1:1, so 0.99e18 to 1.01e18 is acceptable
        assertGt(rateScaled, 0.99e18, "Rate too low - not trading at ~1:1");
        assertLt(rateScaled, 1.01e18, "Rate too high - not trading at ~1:1");

        console.log("SUCCESS: Pool trading at ~1:1 rate");
    }

    function _createPoolAndGetTick() internal returns (address poolAddr, int24 baseTick) {
        uint160 sqrtPriceX96 = _getSqrtPriceX96ForOneToOne();
        poolAddr = nftManager.createAndInitializePoolIfNecessary(token0, token1, FEE_100, sqrtPriceX96);
        (, baseTick,,,,,) = IUniswapV3Pool(poolAddr).slot0();
    }

    function _approveTokens() internal {
        dusd.approve(UNISWAP_V3_NFT_POSITION_MANAGER, type(uint256).max);
        usdc.approve(UNISWAP_V3_NFT_POSITION_MANAGER, type(uint256).max);
    }

    function _mintAndLog(int24 tickLower, int24 tickUpper, uint256 dusdAmt, uint256 usdcAmt) internal {
        (uint256 id,, uint256 a0, uint256 a1) = _mintPosition(tickLower, tickUpper, dusdAmt, usdcAmt);
        console.log("NFT ID:", id);
        _logActualDeposit(a0, a1);
    }

    function _getSqrtPriceX96ForOneToOne() internal view returns (uint160) {
        // For 1 DUSD = 1 USDC with 18 vs 6 decimals:
        // price = 1e6 / 1e18 = 1e-12 (if DUSD is token0)
        // sqrtPrice = 1e-6
        // sqrtPriceX96 = 1e-6 * 2^96 = 79228162514264337593543

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

    function _mintTokens() internal {
        // Mint DUSD
        dusd.setMinterStatus(DEPLOYER, true);
        dusd.setMinterCeiling(DEPLOYER, 500_000 ether);
        dusd.mint(DEPLOYER, 400_000 ether);

        // Get USDC
        deal(address(usdc), DEPLOYER, 1_500_000 * 1e6);
    }

    function _mintPosition(int24 tickLower, int24 tickUpper, uint256 dusdDesired, uint256 usdcDesired)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        return nftManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE_100,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: dusdIsToken0 ? dusdDesired : usdcDesired,
                amount1Desired: dusdIsToken0 ? usdcDesired : dusdDesired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: DEPLOYER,
                deadline: block.timestamp + 1 hours
            })
        );
    }

    function _logActualDeposit(uint256 amount0, uint256 amount1) internal view {
        if (dusdIsToken0) {
            console.log("  DUSD deposited:", amount0 / 1e18);
            console.log("  USDC deposited:", amount1 / 1e6);
        } else {
            console.log("  USDC deposited:", amount0 / 1e6);
            console.log("  DUSD deposited:", amount1 / 1e18);
        }
    }
}

contract SwapHelper {
    IUniswapV3Pool public immutable pool;

    constructor(IUniswapV3Pool _pool) {
        pool = _pool;
    }

    function swap(bool zeroForOne, int256 amountSpecified, address recipient) external {
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? 4295128740  // MIN_SQRT_RATIO + 1
            : 1461446703485210103287273052203988822378723970341; // MAX_SQRT_RATIO - 1

        pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, abi.encode(msg.sender));
    }

    /// @notice Uniswap V3 swap callback - pays the pool
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(pool), "Not pool");

        if (amount0Delta > 0) {
            IERC20(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
        }
    }
}

