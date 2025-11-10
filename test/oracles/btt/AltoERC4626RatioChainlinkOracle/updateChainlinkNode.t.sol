// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoERC4626RatioChainlinkOracleCommon} from "./AltoERC4626RatioChainlinkOracleCommon.t.sol";
import {MockAltoERC4626RatioChainlinkOracle} from "../mocks/MockAltoERC4626RatioChainlinkOracle.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoERC4626RatioChainlinkOracleEvents} from "@alto/oracles/interfaces/IAltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoERC4626RatioChainlinkOracleUpdateChainlinkNode is AltoERC4626RatioChainlinkOracleCommon {
    MockAltoERC4626RatioChainlinkOracle oracle;

    function setUp() public override {
        super.setUp();
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);
        oracle = new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
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
        ChainlinkNode memory validNode = _createValidChainlinkNode(18, 36);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateChainlinkNode(validNode);
    }

    function test_RevertWhen_NodeFeedIsZeroAddress() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(0)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_RevertWhen_NodeStalePeriodIsZero() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: 0,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_RevertWhen_NodeInDecimalsPlusOutDecimalsIsGreaterThan54() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 30,
            outDecimals: 25, // 30 + 25 = 55 > 54
            direction: ConversionDirection.IN_TO_OUT
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_WhenChainlinkNodeIsValid() external givenCallerIsOwner {
        // Get old node
        (
            AggregatorV3Interface oldFeed,
            ConversionDirection oldDirection,
            uint32 oldStalePeriod,
            uint8 oldInDecimals,
            uint8 oldOutDecimals
        ) = oracle.chainlinkNode();
        ChainlinkNode memory oldNode = ChainlinkNode({
            feed: oldFeed,
            direction: oldDirection,
            stalePeriod: oldStalePeriod,
            inDecimals: oldInDecimals,
            outDecimals: oldOutDecimals
        });

        // Create new node
        ChainlinkNode memory newNode = _createValidChainlinkNode2(10, 18);

        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioChainlinkOracleEvents.SetChainlinkNode(oldNode, newNode);

        vm.prank(OWNER);
        oracle.updateChainlinkNode(newNode);

        // it should replace existing chainlinkNode
        // Verify old node is replaced

        // it should update chainlinkNode correctly
        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), address(mockFeed2));
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 10);
        assertEq(outDecimals, 18);
    }
}
