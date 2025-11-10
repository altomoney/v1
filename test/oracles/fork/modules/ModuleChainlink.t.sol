// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";

contract ModuleChainlinkTest is Test {
    ModuleChainlink moduleChainlink;
    address constant USDC_ETH_PRICE_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4; // chainlink feed for USDC/ETH
    address constant BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // chainlink feed for BTC/USD
    address OWNER = makeAddr("Alto-multisig");

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23447653);
        moduleChainlink = new ModuleChainlink();
    }

    function testGetPriceEthUsd() public view {
        uint256 ethQuoteAmount = 10 ** 18;
        // getting the vaule in 8 output decimals
        uint256 usdcAmount = moduleChainlink.readChainlinkFeed(
            ethQuoteAmount,
            ChainlinkNode(AggregatorV3Interface(USDC_ETH_PRICE_FEED), ConversionDirection.OUT_TO_IN, 2 days, 18, 6)
        );
        assertGt(usdcAmount, 0, "Invalid usdcAmount in ChainlinkModule");

        // price is 3976579603. which means 1 ETH is 3976.579603 USDC
        console2.log("price of ETH/USDC from ChainlinkModule", usdcAmount);

        (, int256 answer,,,) = AggregatorV3Interface(USDC_ETH_PRICE_FEED).latestRoundData();
        uint256 answerDecimals = AggregatorV3Interface(USDC_ETH_PRICE_FEED).decimals();
        uint256 ethUsdcExpectedPrice =
            ethQuoteAmount * (10 ** answerDecimals) * (10 ** 6) / (uint256(answer) * (10 ** 18));
        // chainlink feed is in 8 decimals
        // ethUSD price from chainlink is 392246560655. which means 1 ETH is 3922.46560655 USD
        console2.log("ethUsdcPrice from Chainlink feed", ethUsdcExpectedPrice);

        assertEq(usdcAmount, ethUsdcExpectedPrice, "Invalid price in ChainlinkModule");
    }

    function testGetPriceBtcUsd() public view {
        uint256 btcQuoteAmount = 10 ** 8;
        // getting the vaule in 8 output decimals
        uint256 usdAmount = moduleChainlink.readChainlinkFeed(
            btcQuoteAmount,
            ChainlinkNode(AggregatorV3Interface(BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 days, 8, 8)
        );
        assertGt(usdAmount, 0, "Invalid usdAmount in ChainlinkModule");

        console2.log("price of BTC/USD from ChainlinkModule", usdAmount);

        (, int256 answer,,,) = AggregatorV3Interface(BTC_USD_PRICE_FEED).latestRoundData();
        uint256 btcUsdExpectedPrice = uint256(answer);
        // chainlink feed is in 8 decimals
        // btcUSD price from Chainlink is 10952507971300. which means 1 BTC is 10952.5079713 USD
        console2.log("btcUsdPrice from Chainlink feed", btcUsdExpectedPrice);

        assertEq(usdAmount, btcUsdExpectedPrice, "Invalid price in ChainlinkModule");
    }
}
