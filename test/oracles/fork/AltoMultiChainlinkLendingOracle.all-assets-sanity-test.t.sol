// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

contract AltoMultiChainlinkLendingOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    function test_GetPrice_CbBtc() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689559);

        address CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 36
        );
        AltoMultiChainlinkLendingOracle oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        uint256 chainlinkDecimals = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).decimals();

        uint256 price = oracle.getPrice();
        assertEq(
            price,
            chainlinkPrice * (10 ** (nodes[0].outDecimals - chainlinkDecimals)),
            "Incorrect price returned for CbBTC"
        );
    }

    function test_GetPrice_Tbtc() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23489205);

        address CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        AltoMultiChainlinkLendingOracle oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        uint256 chainlinkDecimals = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).decimals();

        uint256 price = oracle.getPrice();
        assertEq(
            price,
            chainlinkPrice * (10 ** (nodes[0].outDecimals - chainlinkDecimals)),
            "Incorrect price returned for TBTC"
        );
    }

    function test_GetPrice_WBtc() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689416);

        address CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
        address CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

        ChainlinkNode[] memory nodes = new ChainlinkNode[](2);
        nodes[0] = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED), ConversionDirection.IN_TO_OUT, 26 hours, 8, 8
        );
        nodes[1] = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 36
        );
        AltoMultiChainlinkLendingOracle oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);

        uint256 price = oracle.getPrice();
        assertApproxEqRel(
            price, chainlinkPrice * (10 ** (nodes[1].outDecimals - nodes[1].inDecimals)), 1e15, "Invalid price for WBTC"
        );
    }

    function test_GetPrice_Weth() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23474424);

        address CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT,
            stalePeriod: 2 hours,
            inDecimals: 18,
            outDecimals: 36
        });
        AltoMultiChainlinkLendingOracle oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);

        uint256 price = oracle.getPrice();
        assertApproxEqRel(price, 4185 * ORACLE_PRICE_PRECISION, 1e15, "Invalid price for WETH (approx)");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);

        uint256 expectedAnswer = (chainlinkPrice * 1e36) / 1e8;
        assertEq(expectedAnswer, price, "Invalid price for WETH (exact)");
    }
}

