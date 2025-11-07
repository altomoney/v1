// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/lending/AltoMultiChainlinkLendingOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoMultiChainlinkLendingOracleEvents} from "@alto/oracles/interfaces/IAltoMultiChainlinkLendingOracle.sol";

contract AltoWethLendingOracleTest is Test {
    AltoMultiChainlinkLendingOracle public altoWethLendingOracle;
    address public OWNER = makeAddr("Alto-multisig");
    address public constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    ChainlinkNode public chainlinkNode;
    ChainlinkNode[] public chainlinkNodes;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23474424);
        chainlinkNodes.push(
            ChainlinkNode({
                feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
                direction: ConversionDirection.IN_TO_OUT,
                stalePeriod: 2 hours,
                inDecimals: 18,
                outDecimals: 36
            })
        );
        altoWethLendingOracle = new AltoMultiChainlinkLendingOracle(OWNER, chainlinkNodes);
    }

    function testGetPrice() public view {
        uint256 price = altoWethLendingOracle.getPrice();
        console2.log("price from AltoWethLendingOracle", price);

        assertApproxEqRel(price, 4185 * ORACLE_PRICE_PRECISION, 1e15, "Invalid price from AltoWethLendingOracle");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        // output precision should be in 36
        // chainlinkPrice is in 8 decimals
        uint256 expectedAnswer = (chainlinkPrice * 1e36) / 1e8;

        assertEq(expectedAnswer, price, "Invalid price from expected and actual price from AltoWethLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkNodes() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWethLendingOracle.updateChainlinkNodes(chainlinkNodes);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 18
        );
        ChainlinkNode[] memory newChainlinkNodes = new ChainlinkNode[](1);
        newChainlinkNodes[0] = newChainlinkNode;
        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(chainlinkNodes, newChainlinkNodes);
        altoWethLendingOracle.updateChainlinkNodes(newChainlinkNodes);

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals
        ) = altoWethLendingOracle.chainlinkNodes(0);
        assertEq(address(feed), CHAINLINK_ETH_USD_PRICE_FEED, "Invalid chainlink feed");
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT), "Invalid chainlink direction");
        assertEq(stalePeriod, 2 hours, "Invalid chainlink stale period");
        assertEq(inDecimals, 18, "Invalid chainlink in decimals");
        assertEq(outDecimals, 18, "Invalid chainlink out decimals");

        vm.expectRevert();
        altoWethLendingOracle.chainlinkNodes(1);
        vm.stopPrank();
    }
}
