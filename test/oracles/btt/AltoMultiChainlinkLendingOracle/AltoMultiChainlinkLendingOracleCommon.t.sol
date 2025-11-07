// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/lending/AltoMultiChainlinkLendingOracle.sol";
import {MockChainlinkFeed} from "../mocks/MockChainlinkFeed.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoMultiChainlinkLendingOracleCommon is Test {
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);

    MockChainlinkFeed mockFeed1;
    MockChainlinkFeed mockFeed2;
    ChainlinkNode chainlinkNode1;
    ChainlinkNode chainlinkNode2;

    // Default valid parameters
    uint32 constant DEFAULT_STALE_PERIOD = 1 days;

    function setUp() public virtual {
        mockFeed1 = new MockChainlinkFeed();
        mockFeed2 = new MockChainlinkFeed();
    }

    function _createValidChainlinkNode1(uint8 inDecimals, uint8 outDecimals)
        internal
        view
        returns (ChainlinkNode memory)
    {
        return ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: inDecimals,
            outDecimals: outDecimals,
            direction: ConversionDirection.IN_TO_OUT
        });
    }

    function _createValidChainlinkNode2(uint8 inDecimals, uint8 outDecimals)
        internal
        view
        returns (ChainlinkNode memory)
    {
        return ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed2)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: inDecimals,
            outDecimals: outDecimals,
            direction: ConversionDirection.IN_TO_OUT
        });
    }

    function _createValidChainlinkNodes(uint8 inDecimals, uint8 outDecimals)
        internal
        view
        returns (ChainlinkNode[] memory)
    {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = _createValidChainlinkNode1(inDecimals, outDecimals);
        return nodes;
    }

    function _createValidChainlinkNodesMulti(uint8 inDecimals1, uint8 outDecimals1, uint8 outDecimals2)
        internal
        view
        returns (ChainlinkNode[] memory)
    {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](2);
        nodes[0] = _createValidChainlinkNode1(inDecimals1, outDecimals1);
        nodes[1] = _createValidChainlinkNode2(outDecimals1, outDecimals2);
        return nodes;
    }
}
