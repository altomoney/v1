// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {console} from "forge-std/console.sol";

contract DeployAltoWBtcLendingOracleScript is Script {
    address public oracle;
    address public owner;
    ChainlinkNode[] public chainlinkNodes;
    address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    function run() public {
        vm.startBroadcast();

        owner = msg.sender;
        ChainlinkNode memory chainlinkNode1 = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED),
            direction: ConversionDirection.IN_TO_OUT,
            stalePeriod: 26 hours,
            inDecimals: 8,
            outDecimals: 8
        });
        ChainlinkNode memory chainlinkNode2 = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT,
            stalePeriod: 2 hours,
            inDecimals: 8,
            outDecimals: 36
        });
        chainlinkNodes.push(chainlinkNode1);
        chainlinkNodes.push(chainlinkNode2);
        oracle = address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));

        console.log("AltoWBtcLendingOracle deployed to:", address(oracle));
        console.log("Owner:", owner);

        vm.stopBroadcast();
    }
}
