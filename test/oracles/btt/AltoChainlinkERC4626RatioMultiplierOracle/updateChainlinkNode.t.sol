// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoChainlinkERC4626RatioMultiplierOracleCommon} from "./AltoChainlinkERC4626RatioMultiplierOracleCommon.t.sol";
import {
    AltoChainlinkERC4626RatioMultiplierOracle
} from "@alto/oracles/AltoChainlinkERC4626RatioMultiplierOracle/AltoChainlinkERC4626RatioMultiplierOracle.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoChainlinkERC4626RatioMultiplierOracleEvents
} from "@alto/oracles/interfaces/IAltoChainlinkERC4626RatioMultiplierOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoChainlinkERC4626RatioMultiplierOracleUpdateChainlinkNode is
    AltoChainlinkERC4626RatioMultiplierOracleCommon
{
    AltoChainlinkERC4626RatioMultiplierOracle oracle;

    function setUp() public override {
        super.setUp();
        oracle = _deployOracle();
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
        ChainlinkNode memory validNode = _createValidChainlinkNode(18, 18);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateChainlinkNode(validNode);
    }

    function test_RevertWhen_NodeFeedIsZeroAddress() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(0)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 18,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
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
            outDecimals: 18,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
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
            outDecimals: 25,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_RevertWhen_NodeFeedDecimalsDoesNotMatchFeedDecimals() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 18,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 6
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_WhenChainlinkNodeIsValid() external givenCallerIsOwner {
        (
            AggregatorV3Interface oldFeed,
            ConversionDirection oldDirection,
            uint32 oldStalePeriod,
            uint8 oldInDecimals,
            uint8 oldOutDecimals,
            uint8 oldFeedDecimals
        ) = oracle.chainlinkNode();
        ChainlinkNode memory oldNode = ChainlinkNode({
            feed: oldFeed,
            direction: oldDirection,
            stalePeriod: oldStalePeriod,
            inDecimals: oldInDecimals,
            outDecimals: oldOutDecimals,
            feedDecimals: oldFeedDecimals
        });

        ChainlinkNode memory newNode = _createValidChainlinkNode2(10, 18);

        vm.expectEmit(true, true, true, true);
        emit IAltoChainlinkERC4626RatioMultiplierOracleEvents.SetChainlinkNode(oldNode, newNode);

        vm.prank(OWNER);
        oracle.updateChainlinkNode(newNode);

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), address(mockFeed2));
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 10);
        assertEq(outDecimals, 18);
        assertEq(feedDecimals, 8);
    }
}
