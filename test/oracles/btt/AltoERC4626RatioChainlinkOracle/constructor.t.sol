// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoERC4626RatioChainlinkOracleCommon} from "./AltoERC4626RatioChainlinkOracleCommon.t.sol";
import {MockAltoERC4626RatioChainlinkOracle} from "../mocks/MockAltoERC4626RatioChainlinkOracle.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoERC4626RatioChainlinkOracleEvents} from "@alto/oracles/interfaces/IAltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoERC4626RatioChainlinkOracleConstructor is AltoERC4626RatioChainlinkOracleCommon {
    modifier givenInvalidInputs() {
        _;
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_ERC4626RatioNodeInitialRatioIsZero() external givenInvalidInputs {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory erc4626RatioNode =
            _createValidERC4626RatioNode(0, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_RevertWhen_ERC4626RatioNodeInitialTimestampIsGreaterThanBlockTimestamp() external givenInvalidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode(
            DEFAULT_INITIAL_RATIO, block.timestamp + 1, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_RevertWhen_ERC4626RatioNodeMaxYearlyGrowthRatioWadIsZero() external givenInvalidInputs {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, 0);
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_RevertWhen_ChainlinkNodeFeedIsZeroAddress() external givenInvalidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(0)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_RevertWhen_ChainlinkNodeStalePeriodIsZero() external givenInvalidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: 0,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: mockFeed1.decimals()
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_RevertWhen_ChainlinkNodeInDecimalsPlusOutDecimalsIsGreaterThan54() external givenInvalidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 30,
            outDecimals: 25, // 30 + 25 = 55 > 54
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: mockFeed1.decimals()
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new MockAltoERC4626RatioChainlinkOracle(address(0), erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    function test_WhenValidInputsAreProvided() external givenValidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);

        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioChainlinkOracleEvents.SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), erc4626RatioNode);

        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioChainlinkOracleEvents.SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0, 0), chainlinkNode
        );

        MockAltoERC4626RatioChainlinkOracle oracle =
            new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);

        // it should set erc4626RatioNode correctly
        (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, DEFAULT_INITIAL_RATIO);
        uint256 expectedTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        assertEq(initialTimestamp, expectedTimestamp);
        assertEq(maxYearlyGrowthRatioWad, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        // it should set chainlinkNode correctly
        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), address(mockFeed1));
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 18);
        assertEq(outDecimals, 36);
        assertEq(feedDecimals, mockFeed1.decimals());

        // it should set owner correctly
        assertEq(oracle.owner(), OWNER);
    }
}
