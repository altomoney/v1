// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {RewardsOracle} from "@alto/oracles/RewardsOracle.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
// import {INonfungiblePositionManager} from "@alto-test/oracles/interfaces/INonfungiblePositionManager.sol";

contract AltoRewardsOracleTest is Test {
    AltoToken altoToken;
    RewardsOracle rewardsOracle;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV3Factory constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address constant ENDPOINTV2 = 0x1a44076050125825900e736c501f859c50fE728c;
    // INonfungiblePositionManager constant NONFUNGIBLE_POSITION_MANAGER =
    //     INonfungiblePositionManager(0x91ae842A5Ffd8d12023116943e72A606179294f3);
    IUniswapV3Pool altoEthPool;
    uint256 wethAmountInPool = 30_000 ether;
    uint256 altoAmountInPool = 10_000_000 ether;
    uint24 constant poolFee = 3000;

    address public OWNER = makeAddr("Alto-multisig");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_RPC_URL"), 23368665);

        vm.startPrank(OWNER);
        altoToken = new AltoToken(ENDPOINTV2, OWNER);

        altoEthPool = IUniswapV3Pool(UNISWAP_V3_FACTORY.createPool(address(altoToken), WETH, poolFee));

        deal(WETH, OWNER, wethAmountInPool);

        // IERC20(WETH).approve(address(NONFUNGIBLE_POSITION_MANAGER), wethAmountInPool);
        // altoToken.approve(address(NONFUNGIBLE_POSITION_MANAGER), altoAmountInPool);

        // INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
        //     token0: address(altoToken),
        //     token1: WETH,
        //     fee: poolFee,
        //     tickLower: TickMath.MIN_TICK,
        //     tickUpper: TickMath.MAX_TICK,
        //     amount0Desired: altoAmountInPool,
        //     amount1Desired: wethAmountInPool,
        //     amount0Min: 0,
        //     amount1Min: 0,
        //     recipient: OWNER,
        //     deadline: block.timestamp
        // });

        // Note that the pool defined by DAI/USDC and fee tier 0.3% must already be created and initialized in order to mint
        // (,,,) = NONFUNGIBLE_POSITION_MANAGER.mint(params);

        vm.stopPrank();
    }

    function test_getPrice1() public view {
        // uint256 price = rewardsOracle.getPrice();
        // assertEq(price, 1);
    }
}
