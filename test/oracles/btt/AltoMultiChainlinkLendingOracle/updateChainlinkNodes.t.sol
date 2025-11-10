// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoMultiChainlinkLendingOracleCommon} from "./AltoMultiChainlinkLendingOracleCommon.t.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoMultiChainlinkLendingOracleErrors,
    IAltoMultiChainlinkLendingOracleEvents
} from "@alto/oracles/interfaces/IAltoMultiChainlinkLendingOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoMultiChainlinkLendingOracleUpdateChainlinkNodes is AltoMultiChainlinkLendingOracleCommon {
    AltoMultiChainlinkLendingOracle oracle;

    function setUp() public override {
        super.setUp();
        ChainlinkNode[] memory nodes = _createValidChainlinkNodes(18, 36);
        oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);
    }

    modifier givenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        ChainlinkNode[] memory validNodes = _createValidChainlinkNodes(18, 36);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateChainlinkNodes(validNodes);
    }

    function test_WhenChainlinkNodesArrayIsEmpty() external givenCallerIsOwner {
        ChainlinkNode[] memory emptyNodes = new ChainlinkNode[](0);

        vm.prank(OWNER);
        vm.expectRevert(IAltoMultiChainlinkLendingOracleErrors.AltoMultiChainlinkLendingOracleInvalidInput.selector);
        oracle.updateChainlinkNodes(emptyNodes);
    }

    function test_RevertWhen_NodeFeedIsZeroAddress() external givenCallerIsOwner {
        ChainlinkNode[] memory invalidNodes = new ChainlinkNode[](1);
        invalidNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(0)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNodes(invalidNodes);
    }

    function test_RevertWhen_NodeStalePeriodIsZero() external givenCallerIsOwner {
        ChainlinkNode[] memory invalidNodes = new ChainlinkNode[](1);
        invalidNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: 0,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNodes(invalidNodes);
    }

    function test_RevertWhen_NodeInDecimalsPlusOutDecimalsIsGreaterThan54() external givenCallerIsOwner {
        ChainlinkNode[] memory invalidNodes = new ChainlinkNode[](1);
        invalidNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 30,
            outDecimals: 25, // 30 + 25 = 55 > 54
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNodes(invalidNodes);
    }

    function test_WhenUpdatingWithSingleNode() external givenCallerIsOwner {
        ChainlinkNode[] memory newNodes = new ChainlinkNode[](1);
        newNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed2)),
            stalePeriod: 2 days,
            inDecimals: 10,
            outDecimals: 18,
            direction: ConversionDirection.OUT_TO_IN
        });

        uint256 oldLength = 1;
        ChainlinkNode[] memory oldNodes = new ChainlinkNode[](oldLength);
        for (uint256 i = 0; i < oldLength; i++) {
            (
                AggregatorV3Interface feed,
                ConversionDirection direction,
                uint32 stalePeriod,
                uint8 inDecimals,
                uint8 outDecimals
            ) = oracle.chainlinkNodes(i);
            oldNodes[i] = ChainlinkNode({
                feed: feed,
                direction: direction,
                stalePeriod: stalePeriod,
                inDecimals: inDecimals,
                outDecimals: outDecimals
            });
        }

        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(oldNodes, newNodes);

        vm.prank(OWNER);
        oracle.updateChainlinkNodes(newNodes);

        // it should replace all existing nodes
        // Test that we can access index 0 but not index 1
        oracle.chainlinkNodes(0);
        vm.expectRevert();
        oracle.chainlinkNodes(1);

        // it should update chainlinkNodes array correctly
        (
            AggregatorV3Interface feed0,
            ConversionDirection direction0,
            uint32 stalePeriod0,
            uint8 inDecimals0,
            uint8 outDecimals0
        ) = oracle.chainlinkNodes(0);
        assertEq(address(feed0), address(mockFeed2));
        assertEq(uint8(direction0), uint8(ConversionDirection.OUT_TO_IN));
        assertEq(stalePeriod0, 2 days);
        assertEq(inDecimals0, 10);
        assertEq(outDecimals0, 18);
    }

    function test_WhenUpdatingWithMultipleNodes() public givenCallerIsOwner {
        ChainlinkNode[] memory newNodes = _createValidChainlinkNodesMulti(18, 18, 36);

        uint256 oldLength = 1;
        ChainlinkNode[] memory oldNodes = new ChainlinkNode[](oldLength);
        for (uint256 i = 0; i < oldLength; i++) {
            (
                AggregatorV3Interface feed,
                ConversionDirection direction,
                uint32 stalePeriod,
                uint8 inDecimals,
                uint8 outDecimals
            ) = oracle.chainlinkNodes(i);
            oldNodes[i] = ChainlinkNode({
                feed: feed,
                direction: direction,
                stalePeriod: stalePeriod,
                inDecimals: inDecimals,
                outDecimals: outDecimals
            });
        }

        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(oldNodes, newNodes);

        vm.prank(OWNER);
        oracle.updateChainlinkNodes(newNodes);

        // it should replace all existing nodes
        // Test that we can access indices 0 and 1 but not index 2
        oracle.chainlinkNodes(0);
        oracle.chainlinkNodes(1);
        vm.expectRevert();
        oracle.chainlinkNodes(2);

        // it should update chainlinkNodes array correctly
        (
            AggregatorV3Interface feed0,
            ConversionDirection direction0,
            uint32 stalePeriod0,
            uint8 inDecimals0,
            uint8 outDecimals0
        ) = oracle.chainlinkNodes(0);
        assertEq(address(feed0), address(mockFeed1));
        assertEq(uint8(direction0), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod0, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals0, 18);
        assertEq(outDecimals0, 18);

        (
            AggregatorV3Interface feed1,
            ConversionDirection direction1,
            uint32 stalePeriod1,
            uint8 inDecimals1,
            uint8 outDecimals1
        ) = oracle.chainlinkNodes(1);
        assertEq(address(feed1), address(mockFeed2));
        assertEq(uint8(direction1), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod1, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals1, 18);
        assertEq(outDecimals1, 36);
    }

    function test_WhenReducingTheNumberOfNodes() public givenCallerIsOwner {
        test_WhenUpdatingWithMultipleNodes();

        uint256 oldLength = 2;
        ChainlinkNode[] memory oldNodes = new ChainlinkNode[](oldLength);
        for (uint256 i = 0; i < oldLength; i++) {
            (
                AggregatorV3Interface feed,
                ConversionDirection direction,
                uint32 stalePeriod,
                uint8 inDecimals,
                uint8 outDecimals
            ) = oracle.chainlinkNodes(i);
            oldNodes[i] = ChainlinkNode({
                feed: feed,
                direction: direction,
                stalePeriod: stalePeriod,
                inDecimals: inDecimals,
                outDecimals: outDecimals
            });
        }

        ChainlinkNode[] memory newNodes = new ChainlinkNode[](1);
        newNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(oldNodes, newNodes);
        oracle.updateChainlinkNodes(newNodes);

        // it should replace all existing nodes
        // Test that we can access index 0 but not index 1
        oracle.chainlinkNodes(0);
        vm.expectRevert();
        oracle.chainlinkNodes(1);

        (
            AggregatorV3Interface feed0,
            ConversionDirection direction0,
            uint32 stalePeriod0,
            uint8 inDecimals0,
            uint8 outDecimals0
        ) = oracle.chainlinkNodes(0);
        assertEq(address(feed0), address(mockFeed1));
        assertEq(uint8(direction0), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod0, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals0, 18);
        assertEq(outDecimals0, 36);
    }
}
