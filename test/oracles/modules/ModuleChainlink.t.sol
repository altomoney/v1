// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";

contract MockChainlinkFeed is AggregatorV3Interface {
    string public description = "Mock Feed";
    uint256 public version = 1;

    uint8 public immutable decimals;
    int256 public immutable ratio;

    constructor(uint8 _decimals, int256 _ratio) {
        decimals = _decimals;
        ratio = _ratio;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, ratio, block.timestamp, block.timestamp, 1);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, ratio, block.timestamp, block.timestamp, 1);
    }
}

contract ModuleChainlinkDecimalsTest is Test {
    ModuleChainlink moduleChainlink;

    function setUp() public {
        moduleChainlink = new ModuleChainlink();
    }

    function testBiggerDecimalToSmallerDecimal() public {
        // WETH/USDC oracle that returns 8 decimals

        // Going from WETH to USDC
        uint256 usdcAmount = moduleChainlink.readChainlinkFeed(
            1e18,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(3000 * 10 ** 8)), // 3000 USDC per WETH
                direction: ConversionDirection.IN_TO_OUT,
                stalePeriod: 2 days,
                inDecimals: 18,
                outDecimals: 6
            })
        );

        assertEq(usdcAmount, 3000e6, "Invalid usdcAmount in ChainlinkModule");

        // Going from USDC to WETH
        uint256 wethAmount = moduleChainlink.readChainlinkFeed(
            4500e6,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(3000 * 10 ** 8)), // 3000 USDC per WETH
                direction: ConversionDirection.OUT_TO_IN,
                stalePeriod: 2 days,
                inDecimals: 6,
                outDecimals: 18
            })
        );

        assertEq(wethAmount, 15e17, "Invalid wethAmount in ChainlinkModule");
    }

    function testSmallerDecimalToBiggerDecimal() public {
        // USDC/WETH oracle that returns 8 decimals

        // Going from USDC to WETH
        uint256 wethAmount = moduleChainlink.readChainlinkFeed(
            6000e6,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(1 / 4000 * 10 ** 8)), // 1/4000 WETH per USDC
                direction: ConversionDirection.IN_TO_OUT,
                stalePeriod: 2 days,
                inDecimals: 6,
                outDecimals: 18
            })
        );

        assertEq(wethAmount, 15e17, "Invalid wethAmount in ChainlinkModule");

        // Going from WETH to USDC
        uint256 usdcAmount = moduleChainlink.readChainlinkFeed(
            1e18,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(1 / 4000 * 10 ** 8)), // 1/4000 WETH per USDC
                direction: ConversionDirection.OUT_TO_IN,
                stalePeriod: 2 days,
                inDecimals: 18,
                outDecimals: 6
            })
        );

        assertEq(usdcAmount, 4000e6, "Invalid usdcAmount in ChainlinkModule");
    }

    function testSameDecimal() public {
        // USDC/USDT oracle that returns 6 decimals

        // Going from USDC to USDC
        uint256 usdtAmount = moduleChainlink.readChainlinkFeed(
            1e6,
            ChainlinkNode({
                feed: new MockChainlinkFeed(6, int256(1.2 * 10 ** 6)), // 1.2 USDT per USDC
                direction: ConversionDirection.IN_TO_OUT,
                stalePeriod: 2 days,
                inDecimals: 6,
                outDecimals: 6
            })
        );

        assertEq(usdtAmount, 12e5, "Invalid usdtAmount in ChainlinkModule");

        // Going from USDT to USDC
        uint256 usdcAmount = moduleChainlink.readChainlinkFeed(
            12e5,
            ChainlinkNode({
                feed: new MockChainlinkFeed(6, int256(1.2 * 10 ** 6)), // 1.2 USDT per USDC
                direction: ConversionDirection.OUT_TO_IN,
                stalePeriod: 2 days,
                inDecimals: 6,
                outDecimals: 6
            })
        );

        assertEq(usdcAmount, 1e6, "Invalid usdcAmount in ChainlinkModule");
    }

    function testSameInAndOracleDecimal() public {
        // WBTC/WETH oracle that returns 8 decimals

        // Going from WBTC to WETH
        uint256 wethAmount = moduleChainlink.readChainlinkFeed(
            1e8,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(25 * 10 ** 8)), // 25 WETH per WBTC
                direction: ConversionDirection.IN_TO_OUT,
                stalePeriod: 2 days,
                inDecimals: 8,
                outDecimals: 18
            })
        );

        assertEq(wethAmount, 25e18, "Invalid wethAmount in ChainlinkModule");

        // Going from WETH to WBTC
        uint256 wbtcAmount = moduleChainlink.readChainlinkFeed(
            25e18,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(25 * 10 ** 8)), // 25 WETH per WBTC
                direction: ConversionDirection.OUT_TO_IN,
                stalePeriod: 2 days,
                inDecimals: 18,
                outDecimals: 8
            })
        );

        assertEq(wbtcAmount, 1e8, "Invalid wbtcAmount in ChainlinkModule");
    }

    function testSameOutAndOracleDecimal() public {
        // WETH/WBTC oracle that returns 8 decimals

        // Going from WETH to WBTC
        uint256 wethAmount = moduleChainlink.readChainlinkFeed(
            1e8,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(25 * 10 ** 8)), // 25 WETH per WBTC
                direction: ConversionDirection.IN_TO_OUT,
                stalePeriod: 2 days,
                inDecimals: 8,
                outDecimals: 18
            })
        );

        assertEq(wethAmount, 25e18, "Invalid wethAmount in ChainlinkModule");

        // Going from WETH to WBTC
        uint256 wbtcAmount = moduleChainlink.readChainlinkFeed(
            25e18,
            ChainlinkNode({
                feed: new MockChainlinkFeed(8, int256(25 * 10 ** 8)), // 25 WETH per WBTC
                direction: ConversionDirection.OUT_TO_IN,
                stalePeriod: 2 days,
                inDecimals: 18,
                outDecimals: 8
            })
        );

        assertEq(wbtcAmount, 1e8, "Invalid wbtcAmount in ChainlinkModule");
    }
}
