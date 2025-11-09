// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {console} from "forge-std/console.sol";

contract DeployAltoTbtcLendingOracleScript is Script {
    address public oracle;
    address public owner;
    ChainlinkNode[] public chainlinkNodes;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    function run() public {
        vm.startBroadcast();

        owner = msg.sender;
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT,
            stalePeriod: 2 hours,
            inDecimals: 18,
            outDecimals: 36
        });
        chainlinkNodes.push(chainlinkNode);
        oracle = address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));

        console.log("AltoTbtcLendingOracle deployed to:", address(oracle));
        console.log("Owner:", owner);

        vm.stopBroadcast();
    }
}
