// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IAltoMultiChainlinkLendingOracleEvents} from "@alto/oracles/interfaces/IAltoMultiChainlinkLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/lending/AltoMultiChainlinkLendingOracle.sol";

contract AltoCbBtcLendingOracleTest is Test {
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    AltoMultiChainlinkLendingOracle internal altoCbBtcLendingOracle;
    ChainlinkNode[] public chainlinkNodes;

    address OWNER = makeAddr("Alto-multisig");
    uint256 chainlinkPrice;
    uint256 chainlinkDecimals;

    function setUp() public {
        chainlinkNodes.push(
            ChainlinkNode(
                AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 36
            )
        );
        altoCbBtcLendingOracle = new AltoMultiChainlinkLendingOracle(OWNER, chainlinkNodes);

        // Fetch chainlink price at forked block
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689559);
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        chainlinkPrice = uint256(chainlinkAnswer);
        chainlinkDecimals = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).decimals();
    }

    function testGetPrice() public view {
        uint256 price = altoCbBtcLendingOracle.getPrice();

        assertEq(
            price,
            chainlinkPrice * (10 ** (chainlinkNodes[0].outDecimals - chainlinkDecimals)),
            "Incorrect price returned by AltoCbBtcLendingOracle"
        );
    }

    function testOnlyOwnerCanUpdateChainlinkNodes() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoCbBtcLendingOracle.updateChainlinkNodes(chainlinkNodes);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode1 = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 8
        );
        ChainlinkNode memory newChainlinkNode2 = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 36
        );
        ChainlinkNode[] memory newChainlinkNodes = new ChainlinkNode[](2);
        newChainlinkNodes[0] = newChainlinkNode1;
        newChainlinkNodes[1] = newChainlinkNode2;
        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(chainlinkNodes, newChainlinkNodes);
        altoCbBtcLendingOracle.updateChainlinkNodes(newChainlinkNodes);

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals
        ) = altoCbBtcLendingOracle.chainlinkNodes(0);
        assertEq(address(feed), CHAINLINK_BTC_USD_PRICE_FEED, "Invalid chainlink feed");
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT), "Invalid chainlink direction");
        assertEq(stalePeriod, 2 hours, "Invalid chainlink stale period");
        assertEq(inDecimals, 8, "Invalid chainlink in decimals");
        assertEq(outDecimals, 8, "Invalid chainlink out decimals");

        (feed, direction, stalePeriod, inDecimals, outDecimals) = altoCbBtcLendingOracle.chainlinkNodes(1);
        assertEq(address(feed), CHAINLINK_BTC_USD_PRICE_FEED, "Invalid chainlink feed");
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT), "Invalid chainlink direction");
        assertEq(stalePeriod, 2 hours, "Invalid chainlink stale period");
        assertEq(inDecimals, 8, "Invalid chainlink in decimals");
        assertEq(outDecimals, 36, "Invalid chainlink out decimals");

        vm.expectRevert();
        altoCbBtcLendingOracle.chainlinkNodes(2);
        vm.stopPrank();
    }
}
