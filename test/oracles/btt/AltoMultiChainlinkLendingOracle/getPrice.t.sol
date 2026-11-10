// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoMultiChainlinkLendingOracleCommon} from "./AltoMultiChainlinkLendingOracleCommon.t.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IAltoMultiChainlinkLendingOracleErrors} from "@alto/oracles/interfaces/IAltoMultiChainlinkLendingOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MockChainlinkFeed} from "../mocks/MockChainlinkFeed.sol";

contract AltoMultiChainlinkLendingOracleGetPrice is AltoMultiChainlinkLendingOracleCommon {
    AltoMultiChainlinkLendingOracle oracle;

    function setUp() public override {
        super.setUp();
    }

    modifier givenChainlinkNodesArrayHasOneNode() {
        ChainlinkNode[] memory nodes = _createValidChainlinkNodes(18, 36);
        oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);
        _;
    }

    modifier givenChainlinkNodesArrayHasMultipleNodes() {
        ChainlinkNode[] memory nodes = _createValidChainlinkNodesMulti(18, 18, 36);
        oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);
        _;
    }

    function test_RevertWhen_ChainlinkNodesArrayIsEmpty() external {
        ChainlinkNode[] memory emptyNodes = new ChainlinkNode[](0);
        vm.expectRevert(IAltoMultiChainlinkLendingOracleErrors.AltoMultiChainlinkLendingOracleInvalidInput.selector);
        oracle = new AltoMultiChainlinkLendingOracle(OWNER, emptyNodes);
    }

    function test_WhenChainlinkFeedReturnsValidPrice_WithOneNode() external givenChainlinkNodesArrayHasOneNode {
        uint256 price = oracle.getPrice();

        // it should return price in 36 decimals
        uint256 expectedPrice = (100000000 * 10 ** 36) / 1e8;
        assertEq(price, expectedPrice);
    }

    function test_WhenAllChainlinkFeedsReturnValidPrices_WithMultipleNodes()
        external
        givenChainlinkNodesArrayHasMultipleNodes
    {
        uint256 price = oracle.getPrice();

        // it should return price in 36 decimals
        assertGt(price, 0);

        uint256 expectedPrice = (100000000 * 10 ** 36) / 1e8;
        assertEq(price, expectedPrice);
    }
}
