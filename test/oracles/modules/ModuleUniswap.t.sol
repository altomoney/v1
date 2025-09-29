// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleUniswap} from "@alto/oracles/lending/modules/ModuleUniswap.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract ModuleUniswapTest is Test {
    ModuleUniswap moduleUniswap;
    address constant WETH_USDC_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // uniswap pool for WETH/USDC
    address constant WBTC_WETH_POOL = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD; // uniswap pool for WBTC/WETH
    address OWNER = makeAddr("Alto-multisig");

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23448120);
        moduleUniswap = new ModuleUniswap();
    }

    function testGetPriceWethUsdc() public view {
        uint256 wethQuoteAmount = 10 ** 18;
        uint256 usdcAmount =
            moduleUniswap.readUniswapPool(wethQuoteAmount, IUniswapV3Pool(WETH_USDC_POOL), 0, 10 minutes);

        assertGt(usdcAmount, 0, "Invalid usdcAmount in UniswapModule");

        console2.log("price of WETH/USDC from UniswapModule", usdcAmount);
        assertGt(usdcAmount, 0, "Invalid usdcAmount in UniswapModule");

        assertApproxEqAbs(usdcAmount, 3959 * 10 ** 6, 1e6);

        uint256 wethAmountBack =
            moduleUniswap.readUniswapPool(usdcAmount, IUniswapV3Pool(WETH_USDC_POOL), 1, 10 minutes);
        assertGt(wethAmountBack, 0, "Invalid wethAmountBack in UniswapModule");

        console2.log("Weth amount back", wethAmountBack);

        assertApproxEqAbs(wethAmountBack, wethQuoteAmount, 1e10);
    }

    function testGetPriceWbtcWeth() public view {
        uint256 wbtcQuoteAmount = 10 ** 8;
        uint256 wethAmount =
            moduleUniswap.readUniswapPool(wbtcQuoteAmount, IUniswapV3Pool(WBTC_WETH_POOL), 1, 10 minutes);

        console2.log("price of WBTC/WETH from UniswapModule", wethAmount);

        assertApproxEqAbs(wethAmount, 27.683366 ether, 1e12, "Invalid wethAmount in UniswapModule");

        uint256 wbtcAmountBack =
            moduleUniswap.readUniswapPool(wethAmount, IUniswapV3Pool(WBTC_WETH_POOL), 0, 10 minutes);
        assertGt(wbtcAmountBack, 0, "Invalid wbtcAmountBack in UniswapModule");

        console2.log("Wbtc amount back", wbtcAmountBack);

        assertApproxEqAbs(wbtcAmountBack, wbtcQuoteAmount, 1e2);
    }

    function testRevertWhenTwapPeriodIsZero() public {
        uint256 wethQuoteAmount = 10 ** 18;
        vm.expectRevert(abi.encodeWithSelector(ModuleUniswap.ModuleUniswapInvalidInput.selector));
        moduleUniswap.readUniswapPool(wethQuoteAmount, IUniswapV3Pool(WETH_USDC_POOL), 0, 0);
    }
}
