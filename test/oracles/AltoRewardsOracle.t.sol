// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {RewardsOracle} from "@alto/oracles/RewardsOracle.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "@alto-test/oracles/interfaces/INonfungiblePositionManager.sol";
import {ChainlinkUtils} from "@alto/oracles/utils/ChainlinkUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

contract AltoRewardsOracleTest is Test {
    // min tick for tick spacing of 200
    int24 constant MIN_TICK = -887200;
    // max tick for tick spacing of 200
    int24 constant MAX_TICK = -MIN_TICK;
    AltoToken altoToken;
    RewardsOracle rewardsOracle;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV3Factory constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address constant ENDPOINTV2 = 0x1a44076050125825900e736c501f859c50fE728c;
    INonfungiblePositionManager constant NONFUNGIBLE_POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    IUniswapV3Pool altoEthPool;
    uint256 wethAmountInPool = 2500 ether;
    uint256 altoAmountInPool = 10_000_000 ether;
    uint24 constant poolFee = 10000;
    bytes32 description = "Alto Rewards Oracle";

    address public OWNER = makeAddr("Alto-multisig");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_RPC_URL"), 23368665);

        vm.startPrank(OWNER);
        altoToken = new AltoToken(ENDPOINTV2, OWNER);

        altoEthPool = IUniswapV3Pool(UNISWAP_V3_FACTORY.createPool(address(altoToken), WETH, poolFee));
        // weth
        console2.log("Token 0 in alToEthPool", altoEthPool.token0());
        // altoToken
        console2.log("Token 1 in alToEthPool", altoEthPool.token1());

        // setting initial price of 1 WETH = ~4000 Alto
        // uniswap sqrtPriceX96 is price of token1 in terms of token0 i.e. (reserve1 / reserve0)
        // Since price is set to 4000, sqrtPriceX96 is Math.sqrt(4000 * 2**192) = 5010828967500.959 ether
        altoEthPool.initialize(5010828967500.959 ether);
        altoEthPool.increaseObservationCardinalityNext(10000);

        deal(WETH, OWNER, wethAmountInPool);

        // approving tokens for providing liquidity
        IERC20(WETH).approve(address(NONFUNGIBLE_POSITION_MANAGER), wethAmountInPool);
        altoToken.approve(address(NONFUNGIBLE_POSITION_MANAGER), altoAmountInPool);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(WETH),
            token1: address(altoToken),
            fee: poolFee,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: wethAmountInPool / 2,
            amount1Desired: altoAmountInPool / 2,
            amount0Min: 0,
            amount1Min: 0,
            recipient: OWNER,
            deadline: block.timestamp
        });
        NONFUNGIBLE_POSITION_MANAGER.mint(params);

        // minting second position
        vm.warp(block.timestamp + 30 minutes);

        params.deadline = block.timestamp;
        NONFUNGIBLE_POSITION_MANAGER.mint(params);

        address[] memory addressInAndOutUni = new address[](2);
        addressInAndOutUni[0] = address(altoToken);
        addressInAndOutUni[1] = WETH;
        IUniswapV3Pool[] memory _circuitUniswap = new IUniswapV3Pool[](1);
        _circuitUniswap[0] = altoEthPool;
        uint8[] memory _circuitUniIsMultiplied = new uint8[](1);
        _circuitUniIsMultiplied[0] = 0;
        uint32 _twapPeriod = 30 minutes;
        uint16 observationLength = 10;
        uint8 _uniFinalCurrency = 1;
        address[] memory _circuitChainlink = new address[](1);
        _circuitChainlink[0] = ETH_USD_PRICE_FEED;
        uint8[] memory _circuitChainIsMultiplied = new uint8[](1);
        _circuitChainIsMultiplied[0] = 1;
        uint32 stalePeriod = 12 hours;

        rewardsOracle = new RewardsOracle(
            addressInAndOutUni,
            _circuitUniswap,
            _circuitUniIsMultiplied,
            _twapPeriod,
            observationLength,
            _uniFinalCurrency,
            _circuitChainlink,
            _circuitChainIsMultiplied,
            OWNER,
            stalePeriod,
            description
        );

        vm.stopPrank();
    }

    function testDeploymentSuccess() public view {
        assertEq(rewardsOracle.owner(), OWNER, "Invalid owner in RewardsOracle");
        assertEq(rewardsOracle.description(), description, "Invalid description in RewardsOracle");
        assertEq(rewardsOracle.inBase(), 10 ** 18, "Invalid inBase in RewardsOracle");
        assertEq(rewardsOracle.outBase(), 10 ** 18, "Invalid outBase in RewardsOracle");
        assertEq(rewardsOracle.uniFinalCurrency(), 1, "Invalid uniFinalCurrency in RewardsOracle");
        assertEq(rewardsOracle.stalePeriod(), 12 hours, "Invalid stalePeriod in RewardsOracle");
        assertEq(rewardsOracle.twapPeriod(), 30 minutes, "Invalid twapPeriod in RewardsOracle");
    }

    function testGetPrice() public view {
        uint256 price = rewardsOracle.getPrice();
        // Price of 1 WETH is 4000 Alto in uniswap pool
        // Price of 1 ETH is 4516 USD in chainlink feed
        // Price of 1 Alto in USD is 1/ 4000 * 4516 =  ~1.129 USD
        assertApproxEqAbs(price, 112900000, 1e6);
    }

    function testOwnerCanUpdateOwner() public {
        address newOwner = makeAddr("New Owner");
        vm.startPrank(OWNER);
        rewardsOracle.transferOwnership(newOwner);
        vm.stopPrank();
        vm.startPrank(newOwner);
        rewardsOracle.acceptOwnership();
        vm.stopPrank();
        assertEq(rewardsOracle.owner(), newOwner, "Invalid owner in RewardsOracle");
    }

    function testOwnerCanUpdateStalePeriod() public {
        vm.startPrank(OWNER);
        rewardsOracle.changeStalePeriod(15 hours);
        vm.stopPrank();
        assertEq(rewardsOracle.stalePeriod(), 15 hours, "Invalid stalePeriod in RewardsOracle");
    }

    function testOwnerCanUpdateTwapPeriod() public {
        vm.startPrank(OWNER);
        rewardsOracle.changeTwapPeriod(45 minutes);
        vm.stopPrank();
        assertEq(rewardsOracle.twapPeriod(), 45 minutes, "Invalid twapPeriod in RewardsOracle");
    }

    function testChainlinkStalePeriodRevert() public {
        vm.startPrank(OWNER);
        rewardsOracle.changeStalePeriod(15 hours);
        vm.stopPrank();
        vm.warp(block.timestamp + 16 hours);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkUtils.InvalidChainlinkRate.selector));
        rewardsOracle.getPrice();
    }
}
