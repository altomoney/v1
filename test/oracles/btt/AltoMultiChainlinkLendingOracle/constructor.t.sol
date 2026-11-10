// SPDX-License-Identifier: GPL-3.0-or-later
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

contract AltoMultiChainlinkLendingOracleConstructor is AltoMultiChainlinkLendingOracleCommon {
    modifier givenInvalidInputs() {
        _;
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_ChainlinkNodesArrayIsEmpty() external givenInvalidInputs {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](0);
        vm.expectRevert(IAltoMultiChainlinkLendingOracleErrors.AltoMultiChainlinkLendingOracleInvalidInput.selector);
        new AltoMultiChainlinkLendingOracle(OWNER, nodes);
    }

    function test_RevertWhen_ChainlinkNodeFeedIsZeroAddress() external givenInvalidInputs {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(0)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoMultiChainlinkLendingOracle(OWNER, nodes);
    }

    function test_RevertWhen_ChainlinkNodeStalePeriodIsZero() external givenInvalidInputs {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: 0,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoMultiChainlinkLendingOracle(OWNER, nodes);
    }

    function test_RevertWhen_ChainlinkNodeInDecimalsPlusOutDecimalsIsGreaterThan54() external givenInvalidInputs {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 30,
            outDecimals: 25, // 30 + 25 = 55 > 54
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoMultiChainlinkLendingOracle(OWNER, nodes);
    }

    function test_RevertWhen_ChainlinkNodeFeedDecimalsDoesNotMatchFeedDecimals() external givenInvalidInputs {
        ChainlinkNode[] memory nodes = new ChainlinkNode[](1);
        nodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 6 // mockFeed1.decimals() returns 8, so this should revert
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoMultiChainlinkLendingOracle(OWNER, nodes);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        ChainlinkNode[] memory nodes = _createValidChainlinkNodes(18, 36);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoMultiChainlinkLendingOracle(address(0), nodes);
    }

    function test_WhenSingleChainlinkNodeIsProvided() external givenValidInputs {
        ChainlinkNode[] memory nodes = _createValidChainlinkNodes(18, 36);

        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(new ChainlinkNode[](0), nodes);

        AltoMultiChainlinkLendingOracle oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);

        // it should set chainlinkNodes array correctly
        // Test that we can access index 0 but not index 1
        oracle.chainlinkNodes(0);
        vm.expectRevert();
        oracle.chainlinkNodes(1);
        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
        ) = oracle.chainlinkNodes(0);
        assertEq(address(feed), address(mockFeed1));
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 18);
        assertEq(outDecimals, 36);

        // it should set owner correctly
        assertEq(oracle.owner(), OWNER);
    }

    function test_WhenMultipleChainlinkNodesAreProvided() external givenValidInputs {
        ChainlinkNode[] memory nodes = _createValidChainlinkNodesMulti(18, 18, 36);

        vm.expectEmit(true, true, true, true);
        emit IAltoMultiChainlinkLendingOracleEvents.SetChainlinkNodes(new ChainlinkNode[](0), nodes);

        AltoMultiChainlinkLendingOracle oracle = new AltoMultiChainlinkLendingOracle(OWNER, nodes);

        // it should set chainlinkNodes array correctly
        // Test that we can access indices 0 and 1 but not index 2
        oracle.chainlinkNodes(0);
        oracle.chainlinkNodes(1);
        vm.expectRevert();
        oracle.chainlinkNodes(2);

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = oracle.chainlinkNodes(0);
        assertEq(address(feed), address(mockFeed1));
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 18);
        assertEq(outDecimals, 18);
        assertEq(feedDecimals, 8);

        (feed, direction, stalePeriod, inDecimals, outDecimals, feedDecimals) = oracle.chainlinkNodes(1);
        assertEq(address(feed), address(mockFeed2));
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 18);
        assertEq(outDecimals, 36);
        assertEq(feedDecimals, 8);

        // it should set owner correctly
        assertEq(oracle.owner(), OWNER);
    }
}
