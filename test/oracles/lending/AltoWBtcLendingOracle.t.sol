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

contract AltoWBtcLendingOracleTest is Test {
    address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    AltoMultiChainlinkLendingOracle internal altoWBtcLendingOracle;
    ChainlinkNode[] public chainlinkNodes;

    address OWNER = makeAddr("Alto-multisig");
    uint256 chainlinkPrice;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689416);
        ChainlinkNode memory chainlinkNode1 = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED), ConversionDirection.IN_TO_OUT, 26 hours, 8, 8
        );
        ChainlinkNode memory chainlinkNode2 = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 36
        );
        chainlinkNodes.push(chainlinkNode1);
        chainlinkNodes.push(chainlinkNode2);
        altoWBtcLendingOracle = (new AltoMultiChainlinkLendingOracle(OWNER, chainlinkNodes));

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        chainlinkPrice = uint256(chainlinkAnswer);
    }

    function testGetPrice() public view {
        uint256 price = altoWBtcLendingOracle.getPrice();

        // Make sure price is approximately within btc/usd price
        assertApproxEqRel(
            price,
            chainlinkPrice * (10 ** (chainlinkNodes[1].outDecimals - chainlinkNodes[1].inDecimals)),
            1e15,
            "Invalid price from AltoWBtcLendingOracle"
        );
    }

    function testOnlyOwnerCanUpdateChainlinkNodes() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWBtcLendingOracle.updateChainlinkNodes(chainlinkNodes);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode1 = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED), ConversionDirection.IN_TO_OUT, 26 hours, 8, 8
        );
        ChainlinkNode[] memory newChainlinkNodes = new ChainlinkNode[](1);
        newChainlinkNodes[0] = newChainlinkNode1;
        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(chainlinkNodes, newChainlinkNodes);
        altoWBtcLendingOracle.updateChainlinkNodes(newChainlinkNodes);

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals
        ) = altoWBtcLendingOracle.chainlinkNodes(0);
        assertEq(address(feed), CHAINLINK_WBTC_BTC_RATIO_FEED, "Invalid chainlink feed");
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT), "Invalid chainlink direction");
        assertEq(stalePeriod, 26 hours, "Invalid chainlink stale period");
        assertEq(inDecimals, 8, "Invalid chainlink in decimals");
        assertEq(outDecimals, 8, "Invalid chainlink out decimals");

        vm.expectRevert();
        altoWBtcLendingOracle.chainlinkNodes(1);
        vm.stopPrank();
    }
}
