// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IAltoMultiChainlinkLendingOracleEvents} from "@alto/oracles/interfaces/IAltoMultiChainlinkLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/lending/AltoMultiChainlinkLendingOracle.sol";

contract AltoTbtcLendingOracleTest is Test {
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    AltoMultiChainlinkLendingOracle internal altoTbtcLendingOracle;
    ChainlinkNode[] public chainlinkNodes;

    address OWNER = makeAddr("Alto-multisig");
    uint256 chainlinkPrice;
    uint256 chainlinkDecimals;

    function setUp() public {
        chainlinkNodes.push(
            ChainlinkNode(
                AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
            )
        );
        altoTbtcLendingOracle = new AltoMultiChainlinkLendingOracle(OWNER, chainlinkNodes);

        // Fetch chainlink price at forked block
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23489205);
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        chainlinkPrice = uint256(chainlinkAnswer);
        chainlinkDecimals = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).decimals();
    }

    function testGetPrice() public view {
        uint256 price = altoTbtcLendingOracle.getPrice();

        assertEq(
            price,
            chainlinkPrice * (10 ** (chainlinkNodes[0].outDecimals - chainlinkDecimals)),
            "Incorrect price returned by AltoTbtcLendingOracle"
        );
    }

    function testOnlyOwnerCanUpdateChainlinkNodes() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoTbtcLendingOracle.updateChainlinkNodes(chainlinkNodes);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        ChainlinkNode[] memory newChainlinkNodes = new ChainlinkNode[](1);
        newChainlinkNodes[0] = newChainlinkNode;
        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(chainlinkNodes, newChainlinkNodes);
        altoTbtcLendingOracle.updateChainlinkNodes(newChainlinkNodes);

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals
        ) = altoTbtcLendingOracle.chainlinkNodes(0);
        assertEq(address(feed), CHAINLINK_BTC_USD_PRICE_FEED, "Invalid chainlink feed");
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT), "Invalid chainlink direction");
        assertEq(stalePeriod, 2 hours, "Invalid chainlink stale period");
        assertEq(inDecimals, 18, "Invalid chainlink in decimals");
        assertEq(outDecimals, 36, "Invalid chainlink out decimals");

        vm.expectRevert();
        altoTbtcLendingOracle.chainlinkNodes(1);
        vm.stopPrank();
    }
}
