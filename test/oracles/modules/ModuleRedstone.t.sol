// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {RedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract ModuleRedstoneTest is Test {
    ModuleRedstone moduleRedstone;
    address constant ETH_USD_PRICE_FEED = 0x197225B3B017eb9b72Ac356D6B3c267d0c04c57c; // redstone feed for ETH/USD
    address constant BTC_USD_PRICE_FEED = 0xbbF121624c3b85C929Ac83872bf6c86b0976A55e; // redstone feed for BTC/USD
    address OWNER = makeAddr("Alto-multisig");

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("arbitrum");
        vm.createSelectFork(rpcUrl, 383169599);
        moduleRedstone = new ModuleRedstone();
    }

    function testGetPriceEthUsd() public view {
        uint256 ethQuoteAmount = 10 ** 18;
        // getting the vaule in 8 output decimals
        uint256 usdAmount = moduleRedstone.readRedstoneFeed(
            ethQuoteAmount, RedstoneNode(AggregatorV3Interface(ETH_USD_PRICE_FEED), 1, 2 days, 18, 8)
        );
        assertGt(usdAmount, 0, "Invalid usdAmount in RedstoneModule");

        // price is 3923480651. which means 1 ETH is 3923.480651 USDC
        console2.log("price of ETH/USDC from RedstoneModule", usdAmount);

        (, int256 answer,,,) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        uint256 ethUsdExpectedPrice = uint256(answer);
        // redstone feed is in 8 decimals
        // ethUSD price from Redstone is 392246560655. which means 1 ETH is 3922.46560655 USD
        console2.log("ethUsdPrice from Redstone feed", ethUsdExpectedPrice);

        assertEq(usdAmount, ethUsdExpectedPrice, "Invalid price in RedstoneModule");
    }

    function testGetPriceBtcUsd() public view {
        uint256 btcQuoteAmount = 10 ** 8;
        // getting the vaule in 8 output decimals
        uint256 usdAmount = moduleRedstone.readRedstoneFeed(
            btcQuoteAmount, RedstoneNode(AggregatorV3Interface(BTC_USD_PRICE_FEED), 1, 2 days, 8, 8)
        );
        assertGt(usdAmount, 0, "Invalid usdAmount in RedstoneModule");

        console2.log("price of BTC/USDC from RedstoneModule", usdAmount);

        (, int256 answer,,,) = AggregatorV3Interface(BTC_USD_PRICE_FEED).latestRoundData();
        uint256 btcUsdExpectedPrice = uint256(answer);
        // redstone feed is in 8 decimals
        // btcUSD price from Redstone is 10952507971300. which means 1 BTC is 10952.5079713 USD
        console2.log("btcUsdPrice from Redstone feed", btcUsdExpectedPrice);

        assertEq(usdAmount, btcUsdExpectedPrice, "Invalid price in RedstoneModule");
    }

    function testRevertWhenPricesAreStale() public {
        uint256 ethQuoteAmount = 10 ** 18;
        vm.expectRevert(abi.encodeWithSelector(ModuleRedstone.ModuleRedstoneInvalidRate.selector));
        moduleRedstone.readRedstoneFeed(
            ethQuoteAmount, RedstoneNode(AggregatorV3Interface(ETH_USD_PRICE_FEED), 1, 1 minutes, 18, 8)
        );
    }
}
