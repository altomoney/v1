// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {console} from "forge-std/console.sol";

contract DeployAltoWethLendingOracleScript is Script {
    address public oracle;
    address public owner;
    ChainlinkNode[] public chainlinkNodes;
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function run() public {
        vm.startBroadcast();

        owner = msg.sender;
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT,
            stalePeriod: 2 hours,
            inDecimals: 18,
            outDecimals: 36
        });
        chainlinkNodes.push(chainlinkNode);
        oracle = address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));

        console.log("AltoWethLendingOracle deployed to:", address(oracle));
        console.log("Owner:", owner);

        vm.stopBroadcast();
    }
}
