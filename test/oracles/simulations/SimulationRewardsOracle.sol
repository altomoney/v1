// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IRewardsOracle} from "@alto/oracles/interfaces/IRewardsOracle.sol";
import {RewardsOracle} from "@alto/oracles/RewardsOracle.sol";
import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {ISwapRouter} from "@alto-test/oracles/interfaces/ISwapRouter.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {AggregatorV3Interface} from "@alto/oracles/utils/ChainlinkUtils.sol";

// TxType that occured in the pool
enum TxType {
    UNKNOWN,
    MINT,
    BURN,
    SWAP
}

// Tx representing JSON object in txData.json
struct Tx {
    uint256 amount;
    int256 amount0;
    int256 amount1;
    uint256 blockNumber;
    int24 tickLower;
    int24 tickUpper;
    uint256 timestamp;
    TxType txType;
}

contract SimulationRewardsOracle is Test {
    uint256 constant TAP_WETH_POOL_DEPLOYMENT_BLOCK = 221966847;
    uint256 constant TAP_WETH_POOL_DRAINED_BLOCK = 265077210;
    address constant ETH_USD_PRICE_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    ISwapRouter constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3Pool TAP_WETH_POOL;
    address OWNER = makeAddr("Alto-multisig");
    RewardsOracle rewardsOracle;
    uint32 constant TWAP_PERIOD = 1 weeks;
    uint32 constant STALE_PERIOD = 36 hours;
    uint256 constant INITIAL_PRICE = 150000000;
    bytes32 description = "TAP-USD Rewards Oracle";
    IUniswapV3Factory UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    AltoToken TAP_TOKEN;
    address MOCK_WETH;
    uint24 constant POOL_FEE = 10000;
    Tx[] txs;

    uint256[] blockNumberTwapPeriodApart = [
        224384693,
        226802041,
        229215137,
        231629647,
        234038363,
        236449739,
        238861183,
        241266825,
        243675854,
        246088404,
        248497205,
        250899855,
        253325872,
        255726321,
        258138636,
        260543662,
        262967691
    ];
    uint256[] timestampsTwapPeriodApart = [
        1719023285,
        1719628105,
        1720232916,
        1720838217,
        1721443090,
        1722048313,
        1722653268,
        1723258513,
        1723864362,
        1724470574,
        1725075712,
        1725680513,
        1726290913,
        1726896476,
        1727502606,
        1728107905,
        1728718895
    ];

    string[] chainlinkPriceDataAtTwapPeriodApart = [
        "00000000000000000000000000000000000000000000000100000000000957aa000000000000000000000000000000000000000000000000000000519813ced00000000000000000000000000000000000000000000000000000000066763698000000000000000000000000000000000000000000000000000000006676369800000000000000000000000000000000000000000000000100000000000957aa",
        "00000000000000000000000000000000000000000000000100000000000965c70000000000000000000000000000000000000000000000000000004ed5818bb000000000000000000000000000000000000000000000000000000000667f6fc400000000000000000000000000000000000000000000000000000000667f6fc400000000000000000000000000000000000000000000000100000000000965c7",
        "000000000000000000000000000000000000000000000001000000000009756e000000000000000000000000000000000000000000000000000000452b3ec388000000000000000000000000000000000000000000000000000000006688aba9000000000000000000000000000000000000000000000000000000006688aba9000000000000000000000000000000000000000000000001000000000009756e",
        "0000000000000000000000000000000000000000000000010000000000098b5200000000000000000000000000000000000000000000000000000048bf9e3d04000000000000000000000000000000000000000000000000000000006691e74c000000000000000000000000000000000000000000000000000000006691e74c0000000000000000000000000000000000000000000000010000000000098b52",
        "0000000000000000000000000000000000000000000000010000000000099d26000000000000000000000000000000000000000000000000000000515813228000000000000000000000000000000000000000000000000000000000669b22eb00000000000000000000000000000000000000000000000000000000669b22eb0000000000000000000000000000000000000000000000010000000000099d26",
        "000000000000000000000000000000000000000000000001000000000009af0f0000000000000000000000000000000000000000000000000000004bc2c3ebd80000000000000000000000000000000000000000000000000000000066a45ca10000000000000000000000000000000000000000000000000000000066a45ca1000000000000000000000000000000000000000000000001000000000009af0f",
        "000000000000000000000000000000000000000000000001000000000009c28f00000000000000000000000000000000000000000000000000000044dd0e7b900000000000000000000000000000000000000000000000000000000066ad9a3e0000000000000000000000000000000000000000000000000000000066ad9a3e000000000000000000000000000000000000000000000001000000000009c28f",
        "000000000000000000000000000000000000000000000001000000000009e5e60000000000000000000000000000000000000000000000000000003cb3b18b780000000000000000000000000000000000000000000000000000000066b6d6240000000000000000000000000000000000000000000000000000000066b6d624000000000000000000000000000000000000000000000001000000000009e5e6",
        "00000000000000000000000000000000000000000000000100000000000a003d0000000000000000000000000000000000000000000000000000003c7c9fdf900000000000000000000000000000000000000000000000000000000066c0146f0000000000000000000000000000000000000000000000000000000066c0146f00000000000000000000000000000000000000000000000100000000000a003d",
        "00000000000000000000000000000000000000000000000100000000000a121a0000000000000000000000000000000000000000000000000000004020f787c00000000000000000000000000000000000000000000000000000000066c953f90000000000000000000000000000000000000000000000000000000066c953f900000000000000000000000000000000000000000000000100000000000a121a",
        "00000000000000000000000000000000000000000000000100000000000a27ac0000000000000000000000000000000000000000000000000000003acccdd6080000000000000000000000000000000000000000000000000000000066d28f2a0000000000000000000000000000000000000000000000000000000066d28f2a00000000000000000000000000000000000000000000000100000000000a27ac",
        "00000000000000000000000000000000000000000000000100000000000a3da3000000000000000000000000000000000000000000000000000000341fbe5ae30000000000000000000000000000000000000000000000000000000066dbcb1e0000000000000000000000000000000000000000000000000000000066dbcb1e00000000000000000000000000000000000000000000000100000000000a3da3",
        "00000000000000000000000000000000000000000000000100000000000a5232000000000000000000000000000000000000000000000000000000387ae9ef000000000000000000000000000000000000000000000000000000000066e51a530000000000000000000000000000000000000000000000000000000066e51a5300000000000000000000000000000000000000000000000100000000000a5232",
        "00000000000000000000000000000000000000000000000100000000000a64fe0000000000000000000000000000000000000000000000000000003b2adcd3f60000000000000000000000000000000000000000000000000000000066ee55920000000000000000000000000000000000000000000000000000000066ee559200000000000000000000000000000000000000000000000100000000000a64fe",
        "00000000000000000000000000000000000000000000000100000000000a77a60000000000000000000000000000000000000000000000000000003e9f93740c0000000000000000000000000000000000000000000000000000000066f798cb0000000000000000000000000000000000000000000000000000000066f798cb00000000000000000000000000000000000000000000000100000000000a77a6",
        "00000000000000000000000000000000000000000000000100000000000a8c740000000000000000000000000000000000000000000000000000003844bdcdfc000000000000000000000000000000000000000000000000000000006700d376000000000000000000000000000000000000000000000000000000006700d37600000000000000000000000000000000000000000000000100000000000a8c74",
        "00000000000000000000000000000000000000000000000100000000000a9ce000000000000000000000000000000000000000000000000000000038f294935c00000000000000000000000000000000000000000000000000000000670a279e00000000000000000000000000000000000000000000000000000000670a279e00000000000000000000000000000000000000000000000100000000000a9ce0"
    ];

    function setUp() public {
        // sets the bytecode in local
        vm.etch(address(UNISWAP_V3_FACTORY), vm.parseBytes(vm.readFile("test/oracles/data/factoryCode.txt")));

        vm.etch(address(SWAP_ROUTER), vm.parseBytes(vm.readFile("test/oracles/data/swapRouterCode.txt")));

        vm.etch(address(ETH_USD_PRICE_FEED), vm.parseBytes(vm.readFile("test/oracles/data/ethUsdPriceFeedCode.txt")));

        // fetches the tx data from json file and populates the txs
        string memory txData = vm.readFile("test/oracles/data/tapWethTxData.json");
        bytes memory txDataBytes = vm.parseJson(txData);
        Tx[] memory _txs = abi.decode(txDataBytes, (Tx[]));

        for (uint256 i = 0; i < _txs.length; i++) {
            txs.push(_txs[i]);
        }

        // sets fee amount in uniswap v3 factory
        // only callable by owner but since bytecode is etched, owner is address(0)
        vm.prank(address(0));
        UNISWAP_V3_FACTORY.enableFeeAmount(10000, 200);

        // creates mock weth and tap tokem
        MOCK_WETH = address(new ERC20MockMintable("MOCK_WETH", "MockWETH"));
        TAP_TOKEN = AltoToken(address(new ERC20MockMintable("MOCK_ALTO", "MockALTO")));

        // initialize uniswap pool with first deployment transaction
        vm.roll(txs[0].blockNumber);
        vm.warp(txs[0].timestamp);
        TAP_WETH_POOL = IUniswapV3Pool(UNISWAP_V3_FACTORY.createPool(address(TAP_TOKEN), MOCK_WETH, POOL_FEE));
        TAP_WETH_POOL.initialize(1931732976923280703113065904);
        TAP_WETH_POOL.mint(address(this), txs[0].tickLower, txs[0].tickUpper, uint128(txs[0].amount), "");

        // increase observation cardinality of the pool to maximum
        for (uint256 i = 1; i < 1000; i++) {
            TAP_WETH_POOL.increaseObservationCardinalityNext(uint16(65 * i));
        }

        // deploys the rewards oracle
        {
            address[] memory addressInAndOutUni = new address[](2);
            addressInAndOutUni[0] = address(TAP_TOKEN);
            addressInAndOutUni[1] = MOCK_WETH;
            IUniswapV3Pool[] memory _circuitUniswap = new IUniswapV3Pool[](1);
            _circuitUniswap[0] = TAP_WETH_POOL;
            uint8[] memory _circuitUniIsMultiplied = new uint8[](1);
            _circuitUniIsMultiplied[0] = 1;
            uint16 observationLength = 10;
            uint8 _uniFinalCurrency = 1;
            address[] memory _circuitChainlink = new address[](1);
            _circuitChainlink[0] = ETH_USD_PRICE_FEED;
            uint8[] memory _circuitChainIsMultiplied = new uint8[](1);
            _circuitChainIsMultiplied[0] = 1;

            IRewardsOracle.RewardsOracleInitParams memory initParams = IRewardsOracle.RewardsOracleInitParams({
                addressInAndOutUni: addressInAndOutUni,
                circuitUniswap: _circuitUniswap,
                circuitUniIsMultiplied: _circuitUniIsMultiplied,
                twapPeriod: TWAP_PERIOD,
                observationLength: observationLength,
                uniFinalCurrency: _uniFinalCurrency,
                circuitChainlink: _circuitChainlink,
                circuitChainIsMultiplied: _circuitChainIsMultiplied,
                owner: OWNER,
                stalePeriod: STALE_PERIOD,
                initialPrice: INITIAL_PRICE,
                description: description
            });

            // mock the chainlink decimals call to return 8
            vm.mockCall(
                ETH_USD_PRICE_FEED, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8)
            );

            // deploys the rewards oracle and starts the twap period
            rewardsOracle = new RewardsOracle(initParams);
            vm.prank(OWNER);
            rewardsOracle.startTwapPeriod();
        }
    }

    function testSimulate_printPriceData() public {
        uint256 weeksProcessed = 0;

        // process all the transactions
        for (uint256 i = 1; i < txs.length; i++) {
            if (txs[i - 1].blockNumber != txs[i].blockNumber) {
                vm.roll(txs[i].blockNumber);
                vm.warp(txs[i].timestamp);
            }

            // if week has passed since last update, updates the reward oracle and fetches the price
            if (
                weeksProcessed < blockNumberTwapPeriodApart.length
                    && txs[i].blockNumber == blockNumberTwapPeriodApart[weeksProcessed]
            ) {
                // mock the chainlink latestRoundData call to return the price at the twap period
                vm.mockCall(
                    ETH_USD_PRICE_FEED,
                    abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
                    vm.parseBytes(chainlinkPriceDataAtTwapPeriodApart[weeksProcessed])
                );

                rewardsOracle.updatePrice();
                console2.log("Processing Week", weeksProcessed + 1);
                console2.log("Block number", txs[i].blockNumber);
                console2.log("Timestamp", txs[i].timestamp);
                console2.log("Price of rewardsOracle is", rewardsOracle.getPrice());
                console2.log("--------------------------------");
                weeksProcessed++;

                vm.clearMockedCalls();
            }

            _processTransaction(txs[i]);
        }
    }

    function testSimulate_sanityCheck() public {
        // We check simulated dataset liquidity agains mainnet liquidity at the following block numbers
        // This is to ensure that the simulated dataset is consistent with the mainnet dataset

        uint256[] memory sanityCheckBlockNumbers = new uint256[](7);
        sanityCheckBlockNumbers[0] = 221966847; // first block included in the dataset
        sanityCheckBlockNumbers[1] = 221966848;
        sanityCheckBlockNumbers[2] = 230000000;
        sanityCheckBlockNumbers[3] = 240000000;
        sanityCheckBlockNumbers[4] = 250000000;
        sanityCheckBlockNumbers[5] = 260000000;
        sanityCheckBlockNumbers[6] = 265076832; // last block included in the dataset

        uint256[] memory localLiquidity = new uint256[](sanityCheckBlockNumbers.length);

        uint256 currentSanityCheckIndex = 0;

        for (uint256 i = 1; i < txs.length; i++) {
            if (txs[i - 1].blockNumber != txs[i].blockNumber) {
                if (sanityCheckBlockNumbers[currentSanityCheckIndex] < txs[i].blockNumber) {
                    localLiquidity[currentSanityCheckIndex] = TAP_WETH_POOL.liquidity();
                    currentSanityCheckIndex++;
                }
                vm.roll(txs[i].blockNumber);
                vm.warp(txs[i].timestamp);
            }

            _processTransaction(txs[i]);
        }

        localLiquidity[currentSanityCheckIndex] = TAP_WETH_POOL.liquidity();

        for (uint256 i = 0; i < sanityCheckBlockNumbers.length; i++) {
            string memory rpcUrl = vm.rpcUrl("arbitrum");
            vm.createSelectFork(rpcUrl, sanityCheckBlockNumbers[i]);
            uint256 liquidityMainnet = IUniswapV3Pool(0x5918AcA9ae924e6EaAA3d293Bb92BDEc9Ab79338).liquidity();
            assertEq(
                localLiquidity[i],
                liquidityMainnet,
                string(
                    abi.encodePacked(
                        "Liquidity at block ",
                        vm.toString(sanityCheckBlockNumbers[i]),
                        " is not equal to mainnet liquidity"
                    )
                )
            );
        }
    }

    function _processTransaction(Tx memory _transaction) internal {
        TxType txType = _transaction.txType;
        if (txType == TxType.MINT) {
            deal(address(TAP_TOKEN), address(this), uint256(_transaction.amount0));
            deal(MOCK_WETH, address(this), uint256(_transaction.amount1));
            TAP_WETH_POOL.mint(
                address(this), _transaction.tickLower, _transaction.tickUpper, uint128(_transaction.amount), ""
            );
        } else if (txType == TxType.BURN) {
            TAP_WETH_POOL.burn(_transaction.tickLower, _transaction.tickUpper, uint128(_transaction.amount));
        } else if (txType == TxType.SWAP) {
            if (_transaction.amount0 < 0) {
                _swapOnUniswap(MOCK_WETH, address(TAP_TOKEN), _transaction.amount0);
            } else if (_transaction.amount1 < 0) {
                _swapOnUniswap(address(TAP_TOKEN), MOCK_WETH, _transaction.amount1);
            }
        }
    }

    function _swapOnUniswap(address tokenIn, address tokenOut, int256 amountOut) internal returns (uint256) {
        deal(tokenIn, address(this), type(uint128).max);

        IERC20(tokenIn).approve(address(SWAP_ROUTER), type(uint256).max);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: uint256(-amountOut),
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        uint256 amountIn = SWAP_ROUTER.exactOutputSingle(params);

        return amountIn;
    }

    // DO NOT DELETE THIS FUNCTION. IT IS USED BY UNISWAP V3 POOL DURING MINT
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        deal(address(TAP_TOKEN), address(this), amount0Owed);
        deal(MOCK_WETH, address(this), amount1Owed);
        if (amount0Owed > 0) {
            bool success = TAP_TOKEN.transfer(address(TAP_WETH_POOL), amount0Owed);
            require(success, "Transfer failed");
        }
        if (amount1Owed > 0) {
            bool success = IERC20(MOCK_WETH).transfer(address(TAP_WETH_POOL), amount1Owed);
            require(success, "Transfer failed");
        }
    }
}
