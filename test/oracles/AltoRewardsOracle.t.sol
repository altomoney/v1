// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {ISwapRouter} from "@alto-test/oracles/interfaces/ISwapRouter.sol";
import {console2} from "forge-std/console2.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {INonfungiblePositionManager} from "@alto-test/oracles/interfaces/INonfungiblePositionManager.sol";
import {
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleErrors,
    IAltoRewardsOracleEvents
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {UniswapNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoRewardsOracleTest is Test {
    // min tick for tick spacing of 200
    int24 constant MIN_TICK = -887200;
    // max tick for tick spacing of 200
    int24 constant MAX_TICK = -MIN_TICK;
    AltoToken altoToken;
    AltoRewardsOracle rewardsOracle;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV3Factory constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address constant ENDPOINTV2 = 0x1a44076050125825900e736c501f859c50fE728c;
    INonfungiblePositionManager constant NONFUNGIBLE_POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    ISwapRouter constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    IUniswapV3Pool altoEthPool;
    uint256 wethAmountInPool = 2500 ether;
    uint256 altoAmountInPool = 10_000_000 ether;
    uint24 constant POOL_FEE = 10000;
    bytes32 description = "Alto Rewards Oracle";
    uint32 twapPeriod = 1 hours;
    uint256 priceUpdateCooldownPeriod = 1 weeks;
    // keeping chainlink stale period to be high value because uniswap twap is 1 weeks
    // we need to forward block.timestamp to get twap price of 1 weeks while we lastUpdatedAt won't be updated in chainlink feed
    uint32 stalePeriod = 8 weeks;
    // price at which pool of WETH/ALTO is initialized
    // Price of 1 WETH is 4000 Alto in uniswap pool
    // Price of 1 ETH is 4516 USD in chainlink feed
    // Price of 1 Alto in USD is 1/ 4000 * 4516 =  ~1.129 USD
    uint256 initialPrice = 112900000;

    address public OWNER = makeAddr("Alto-multisig");

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23368665);

        vm.startPrank(OWNER);
        altoToken = new AltoToken(ENDPOINTV2, OWNER);

        altoEthPool = IUniswapV3Pool(UNISWAP_V3_FACTORY.createPool(address(altoToken), WETH, POOL_FEE));
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

        vm.warp(block.timestamp + twapPeriod);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(WETH),
            token1: address(altoToken),
            fee: POOL_FEE,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: wethAmountInPool,
            amount1Desired: altoAmountInPool,
            amount0Min: 0,
            amount1Min: 0,
            recipient: OWNER,
            deadline: block.timestamp
        });
        NONFUNGIBLE_POSITION_MANAGER.mint(params);

        UniswapNode memory uniswapNode = UniswapNode({pool: altoEthPool, twapPeriod: twapPeriod, multiplied: 0});
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(ETH_USD_PRICE_FEED),
            stalePeriod: stalePeriod,
            inDecimals: 18,
            outDecimals: 8,
            multiplied: 1
        });

        AltoRewardsOracleInitParams memory initParams = AltoRewardsOracleInitParams({
            inBase: 10 ** 18,
            uniswapNode: uniswapNode,
            chainlinkNode: chainlinkNode,
            owner: OWNER,
            description: description,
            priceUpdateCooldownPeriod: priceUpdateCooldownPeriod
        });

        rewardsOracle = new AltoRewardsOracle(initParams);

        vm.stopPrank();
    }

    function testDeploymentSuccess() public view {
        assertEq(rewardsOracle.owner(), OWNER, "Invalid owner in AltoRewardsOracle");
        assertEq(rewardsOracle.description(), description, "Invalid description in AltoRewardsOracle");
        assertEq(rewardsOracle.IN_BASE(), 10 ** 18, "Invalid inBase in AltoRewardsOracle");
        assertEq(rewardsOracle.cachedPrice(), 0, "Invalid cachedPrice in AltoRewardsOracle");
        assertEq(rewardsOracle.lastPriceUpdateTimestamp(), 0, "Invalid lastPriceUpdateTimestamp in AltoRewardsOracle");
        assertEq(
            rewardsOracle.priceUpdateCooldownPeriod(),
            priceUpdateCooldownPeriod,
            "Invalid priceUpdateCooldownPeriod in AltoRewardsOracle"
        );
    }

    modifier whenInitiated() {
        vm.startPrank(OWNER);
        rewardsOracle.startTwapPeriod(initialPrice);
        vm.stopPrank();
        _;
    }

    function testGetPriceWhenNotInitiated() public {
        // reverts when twap period is not started
        vm.expectRevert(abi.encodeWithSelector(IAltoRewardsOracleErrors.AltoRewardsOracleNotInitiated.selector));
        rewardsOracle.getPrice();
    }

    function testGetPriceWhenInitiated() public whenInitiated {
        uint256 price = rewardsOracle.getPrice();
        assertEq(price, initialPrice, "Invalid price from AltoRewardsOracle");
    }

    function testStartTwapPeriodRevertsWhenInitiated() public whenInitiated {
        // reverts when twap period is already started
        vm.startPrank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(IAltoRewardsOracleErrors.AltoRewardsOracleAlreadyStartedTwapPeriod.selector)
        );
        rewardsOracle.startTwapPeriod(initialPrice);
        vm.stopPrank();
    }

    function testStartTwapPeriodOnlyCallableByOwner() public {
        // only owner can start twap period
        address user = makeAddr("User");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vm.startPrank(user);
        rewardsOracle.startTwapPeriod(initialPrice);
        vm.stopPrank();

        vm.startPrank(OWNER);
        rewardsOracle.startTwapPeriod(initialPrice);
        vm.stopPrank();
        assertEq(
            rewardsOracle.lastPriceUpdateTimestamp(),
            block.timestamp,
            "Invalid lastPriceUpdateTimestamp in AltoRewardsOracle"
        );
        assertEq(rewardsOracle.cachedPrice(), initialPrice, "Invalid cachedPrice in RewardsOracle");
    }

    function testUpdatePriceRevertsWhenNotInitiated() public {
        // updatePrice reverts when twap period is not started
        // this is to prevent fetching price before twap period is passed after uniswap pool is created
        vm.expectRevert(abi.encodeWithSelector(IAltoRewardsOracleErrors.AltoRewardsOracleNotInitiated.selector));
        rewardsOracle.updatePrice();
    }

    function testUpdatePriceCorrectness() public whenInitiated {
        // updating price before twap period is passed reverts
        vm.expectRevert(
            abi.encodeWithSelector(IAltoRewardsOracleErrors.AltoRewardsOracleTooEarlyToUpdatePrice.selector)
        );
        rewardsOracle.updatePrice();

        assertEq(rewardsOracle.getPrice(), initialPrice, "Invalid price from AltoRewardsOracle");
        assertEq(initialPrice, rewardsOracle.cachedPrice(), "Invalid price from AltoRewardsOracle");

        // updating price after twap period is successful and updates the price based on the uniswap twap period
        vm.warp(block.timestamp + rewardsOracle.priceUpdateCooldownPeriod());
        vm.expectEmit(true, true, true, false);
        emit IAltoRewardsOracleEvents.PriceUpdated(block.timestamp, initialPrice, initialPrice);
        rewardsOracle.updatePrice();

        assertApproxEqAbs(rewardsOracle.getPrice(), initialPrice, 1e5, "Invalid price from AltoRewardsOracle");
        assertEq(
            rewardsOracle.lastPriceUpdateTimestamp(),
            block.timestamp,
            "Invalid lastPriceUpdateTimestamp in AltoRewardsOracle"
        );
        assertApproxEqAbs(rewardsOracle.cachedPrice(), initialPrice, 1e5, "Invalid cachedPrice in RewardsOracle");
        assertEq(
            rewardsOracle.getPrice(),
            rewardsOracle.cachedPrice(),
            "AltoRewardsOracle price and cachedPrice should be equal"
        );

        // updating price before twap period is passed reverts
        vm.expectRevert(
            abi.encodeWithSelector(IAltoRewardsOracleErrors.AltoRewardsOracleTooEarlyToUpdatePrice.selector)
        );
        rewardsOracle.updatePrice();
    }

    function testGetPriceWhenPriceDecreases() public whenInitiated {
        // This scenario covers the case where twap price initially at timestamp T is initialPrice
        // at timestamp t1 = T, twap period is initiated with initialPrice
        // at timestamp t2 =(T + priceUpdateCooldownPeriod - twapPeriod), swap occurs from Alto to WETH
        // at timestamp t3 =(T + priceUpdateCooldownPeriod - twapPeriod / 2), another swap occurs from Alto to WETH
        // at timestamp t4 = (T + priceUpdateCooldownPeriod), price is updated to the new price. new price should be less than initialPrice due to swap
        // at timestamp t4 = (T + priceUpdateCooldownPeriod + twapPeriod / 2), price queried should be the same as price at t4 as it's not updated in between
        assertEq(rewardsOracle.getPrice(), initialPrice, "Invalid price from AltoRewardsOracle");
        assertEq(
            rewardsOracle.getPrice(),
            rewardsOracle.cachedPrice(),
            "AltoRewardsOracle price and initialPrice should be equal"
        );
        vm.warp(block.timestamp + rewardsOracle.priceUpdateCooldownPeriod() - twapPeriod);
        uint256 amountIn = 2_000_000 ether;
        // swapping from Alto to WETH
        _swapOnUniswap(address(altoToken), WETH, amountIn);
        _swapOnUniswap(address(altoToken), WETH, amountIn);

        // forward twapPeriod/2
        vm.warp(block.timestamp + twapPeriod / 2);
        // swapping from Alto to WETH
        _swapOnUniswap(address(altoToken), WETH, amountIn);
        _swapOnUniswap(address(altoToken), WETH, amountIn);

        // forward twapPeriod/2
        vm.warp(block.timestamp + twapPeriod / 2);

        // updating price after priceUpdateCooldownPeriod is successful and updates the price based on the uniswap twap period
        // it will reduce the price due to earlier swaps from Alto to WETH
        rewardsOracle.updatePrice();

        uint256 priceAfterUpdate = rewardsOracle.getPrice();
        console2.log("priceAfterUpdate due to swap is", priceAfterUpdate);
        assertLt(priceAfterUpdate, initialPrice, "Price should decrease due to swap from Alto to WETH");
        assertEq(priceAfterUpdate, rewardsOracle.cachedPrice(), "Invalid cachedPrice in AltoRewardsOracle");

        // price should be the same as price after update because it's not updated in between
        vm.warp(block.timestamp + twapPeriod / 2);
        assertEq(rewardsOracle.getPrice(), priceAfterUpdate, "Invalid price from AltoRewardsOracle");
    }

    function testGetPriceWhenPriceIncreases() public whenInitiated {
        // This scenario covers the case where twap price initially at timestamp T is initialPrice
        // at timestamp t1 = T, price is initiated with initialPrice
        // at timestamp t2 =(T + priceUpdateCooldownPeriod - twapPeriod), swap occurs from WETH to Alto
        // at timestamp t3 =(T + priceUpdateCooldownPeriod - twapPeriod / 2), another swap occurs from WETH to Alto
        // at timestamp t4 = (T + priceUpdateCooldownPeriod), price is updated to the new price. new price should be more than initialPrice due to swap
        // at timestamp t5 = (T + priceUpdateCooldownPeriod + twapPeriod / 2), price queried should be the same as price at t4 as it's not updated in between
        assertEq(rewardsOracle.getPrice(), initialPrice, "Invalid price from AltoRewardsOracle");
        assertEq(
            rewardsOracle.getPrice(),
            rewardsOracle.cachedPrice(),
            "AltoRewardsOracle price and initialPrice should be equal"
        );
        vm.warp(block.timestamp + rewardsOracle.priceUpdateCooldownPeriod() - twapPeriod);

        uint256 amountIn = 10 ether;
        // swapping from WETH to Alto
        _swapOnUniswap(WETH, address(altoToken), amountIn);

        vm.warp(block.timestamp + twapPeriod / 2);
        // swapping from WETH to Alto
        _swapOnUniswap(WETH, address(altoToken), amountIn);

        vm.warp(block.timestamp + twapPeriod / 2);

        // updating price after priceUpdateCooldownPeriod is successful and updates the price based on the uniswap twap period
        // it will increase the price due to earlier swaps from WETH to Alto
        rewardsOracle.updatePrice();

        uint256 priceAfterUpdate = rewardsOracle.getPrice();
        console2.log("priceAfterUpdate due to swap is", priceAfterUpdate);
        assertGt(priceAfterUpdate, initialPrice, "Price should increase due to swap from WETH to Alto");
        assertEq(priceAfterUpdate, rewardsOracle.cachedPrice(), "Invalid cachedPrice in AltoRewardsOracle");

        vm.warp(block.timestamp + twapPeriod / 2);
        // price should be the same as price after update because it's not updated in between
        assertEq(rewardsOracle.getPrice(), priceAfterUpdate, "Invalid price from AltoRewardsOracle");
    }

    function testGetPriceAfterFluctuations() public whenInitiated {
        // This scenario covers the case where twap price initially at timestamp T is initialPrice
        // at timestamp t1 = T, twap period is initiated with initialPrice
        // at timestamp t1 =T + priceUpdateCooldownPeriod, swap occurs from Alto to WETH with output amount of X weth
        // at timestamp t2 =T + priceUpdateCooldownPeriod, swap occurs from X amount ofWETH to Alto
        // at timestamp t3 = (T + priceUpdateCooldownPeriod - twapPeriod), swap occurs from WETH to Alto with output of Y Alto
        // at timestamp t4 = (T + priceUpdateCooldownPeriod - twapPeriod / 2), swap occurs from Y amount of Alto to WETH with output of Z WETH
        // at timestamp t5 = (T + priceUpdateCooldownPeriod), price is updated to the new price. new price should be almost equal to price at T
        // old price will be initialPrice set during deployment
        uint256 oldPrice = rewardsOracle.getPrice();
        uint256 amountOutOfWeth;
        {
            vm.warp(block.timestamp + rewardsOracle.priceUpdateCooldownPeriod() - twapPeriod);
            // swap from Alto to WETH and back to Alto
            uint256 amountIn = 1_000_000 ether;
            // swap from Alto to WETH
            amountOutOfWeth = _swapOnUniswap(address(altoToken), WETH, amountIn);
            assertGt(amountOutOfWeth, 0, "Invalid amountOut from swap");
            // swap from WETH to Alto.
            // amountOutOfWeth is the amount of WETH received from the earlier swap
            _swapOnUniswap(WETH, address(altoToken), amountOutOfWeth);
        }

        vm.warp(block.timestamp + twapPeriod / 2);
        {
            // swap from WETH to Alto
            // amountOutOfWeth is the amount of WETH received from the earlier swap
            uint256 amountOutOfAlto = _swapOnUniswap(WETH, address(altoToken), amountOutOfWeth);
            assertGt(amountOutOfAlto, 0, "Invalid amountOut from swap");
            // swap from Alto to WETH
            _swapOnUniswap(address(altoToken), WETH, amountOutOfAlto);
        }

        vm.warp(block.timestamp + twapPeriod / 2);
        // updating price after twap period is successful and updates the price based on the uniswap twap period
        // it will update the price based on the uniswap twap period
        // new price should be almost equal to old price because swaps are done in such a way that price doesn't change much
        rewardsOracle.updatePrice();
        uint256 newPrice = rewardsOracle.getPrice();
        console2.log("old price is", oldPrice);
        console2.log("new price is", newPrice);
        assertApproxEqAbs(newPrice, oldPrice, 1e5, "Invalid price from RewardsOracle");
    }

    function testGetPriceReturnsCachedPriceWhenNotUpdated() public whenInitiated {
        // price should be the same as initialPrice set during deployment
        assertEq(rewardsOracle.getPrice(), initialPrice, "Invalid price from AltoRewardsOracle");

        vm.warp(block.timestamp + rewardsOracle.priceUpdateCooldownPeriod() + 1);
        // updating price after twap period is successful and updates the price based on the uniswap twap period
        // it will update the price based on the uniswap twap period
        rewardsOracle.updatePrice();
        uint256 priceAfterUpdate = rewardsOracle.getPrice();
        assertEq(priceAfterUpdate, rewardsOracle.cachedPrice(), "Invalid price from AltoRewardsOracle");
        assertApproxEqAbs(priceAfterUpdate, initialPrice, 1e5, "Invalid price from AltoRewardsOracle");

        // price should be the same as cached price as it has not been updated in between
        vm.warp(block.timestamp + 2 * rewardsOracle.priceUpdateCooldownPeriod());
        assertEq(rewardsOracle.getPrice(), priceAfterUpdate, "Invalid price from AltoRewardsOracle");
    }

    function testOwnerCanUpdateOwner() public {
        address newOwner = makeAddr("New Owner");
        vm.startPrank(OWNER);
        rewardsOracle.transferOwnership(newOwner);
        vm.stopPrank();
        vm.startPrank(newOwner);
        rewardsOracle.acceptOwnership();
        vm.stopPrank();
        assertEq(rewardsOracle.owner(), newOwner, "Invalid owner in AltoRewardsOracle");
    }

    function testOwnerCanUpdatePriceUpdateCooldownPeriod() public {
        vm.startPrank(OWNER);
        vm.expectEmit(false, false, false, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(
            rewardsOracle.priceUpdateCooldownPeriod(), 1 hours
        );
        rewardsOracle.updatePriceUpdateCooldownPeriod(1 hours);
        vm.stopPrank();
        assertEq(
            rewardsOracle.priceUpdateCooldownPeriod(), 1 hours, "Invalid priceUpdateCooldownPeriod in AltoRewardsOracle"
        );

        vm.startPrank(makeAddr("User"));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("User")));
        rewardsOracle.updatePriceUpdateCooldownPeriod(1 hours);
        vm.stopPrank();
    }

    function testOwnerCanUpdateUniswapNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        rewardsOracle.updateUniswapNode(UniswapNode({pool: altoEthPool, twapPeriod: twapPeriod, multiplied: 0}));
        vm.stopPrank();

        vm.startPrank(OWNER);
        UniswapNode memory newUniswapNode = UniswapNode({pool: altoEthPool, twapPeriod: 1, multiplied: 0});
        (IUniswapV3Pool pool, uint8 multiplied, uint32 twapPeriod) = rewardsOracle.uniswapNode();
        UniswapNode memory oldUniswapNode = UniswapNode({pool: pool, twapPeriod: twapPeriod, multiplied: multiplied});

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.SetUniswapNode(oldUniswapNode, newUniswapNode);
        rewardsOracle.updateUniswapNode(newUniswapNode);
        vm.stopPrank();
    }

    function testOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        rewardsOracle.updateChainlinkNode(
            ChainlinkNode({
                feed: AggregatorV3Interface(ETH_USD_PRICE_FEED),
                stalePeriod: stalePeriod,
                inDecimals: 18,
                outDecimals: 18,
                multiplied: 0
            })
        );
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(ETH_USD_PRICE_FEED),
            stalePeriod: stalePeriod,
            inDecimals: 18,
            outDecimals: 18,
            multiplied: 0
        });
        (AggregatorV3Interface feed, uint8 multiplied, uint32 stalePeriod, uint8 inDecimals, uint8 outDecimals) =
            rewardsOracle.chainlinkNode();
        ChainlinkNode memory oldChainlinkNode = ChainlinkNode({
            feed: feed,
            stalePeriod: stalePeriod,
            inDecimals: inDecimals,
            outDecimals: outDecimals,
            multiplied: multiplied
        });

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.SetChainlinkNode(oldChainlinkNode, newChainlinkNode);
        rewardsOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }

    function _swapOnUniswap(address tokenIn, address tokenOut, uint256 amountIn) public returns (uint256) {
        address user = makeAddr("User");
        deal(tokenIn, user, amountIn);

        vm.startPrank(user);

        IERC20(tokenIn).approve(address(SWAP_ROUTER), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: POOL_FEE,
            recipient: user,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = SWAP_ROUTER.exactInputSingle(params);

        string memory tokenInSymbol = IERC20Metadata(tokenIn).symbol();
        string memory tokenOutSymbol = IERC20Metadata(tokenOut).symbol();
        string memory message = string.concat(
            "Swapped ",
            Strings.toString(amountIn),
            " ",
            tokenInSymbol,
            " for ",
            Strings.toString(amountOut),
            " ",
            tokenOutSymbol
        );
        console2.log(message);

        vm.stopPrank();

        return amountOut;
    }
}
