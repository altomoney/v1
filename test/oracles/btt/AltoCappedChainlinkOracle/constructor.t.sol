// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoCappedChainlinkOracleCommon} from "./AltoCappedChainlinkOracleCommon.t.sol";
import {AltoCappedChainlinkOracle} from "@alto/oracles/AltoCappedChainlinkOracle/AltoCappedChainlinkOracle.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoCappedChainlinkOracleEvents} from "@alto/oracles/interfaces/IAltoCappedChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoCappedChainlinkOracleConstructor is AltoCappedChainlinkOracleCommon {
    modifier givenInvalidInputs() {
        _;
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoCappedChainlinkOracle(address(0), _createValidChainlinkNode(18, 18), _createValidERC4626RatioNode());
    }

    function test_RevertWhen_ChainlinkNodeFeedIsZeroAddress() external givenInvalidInputs {
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(0)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 18,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, chainlinkNode, _createValidERC4626RatioNode());
    }

    function test_RevertWhen_ChainlinkNodeStalePeriodIsZero() external givenInvalidInputs {
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: 0,
            inDecimals: 18,
            outDecimals: 18,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, chainlinkNode, _createValidERC4626RatioNode());
    }

    function test_RevertWhen_ChainlinkNodeInDecimalsPlusOutDecimalsIsGreaterThan54() external givenInvalidInputs {
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 30,
            outDecimals: 25,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, chainlinkNode, _createValidERC4626RatioNode());
    }

    function test_RevertWhen_ChainlinkNodeFeedDecimalsDoesNotMatchFeedDecimals() external givenInvalidInputs {
        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 18,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 6
        });

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, chainlinkNode, _createValidERC4626RatioNode());
    }

    function test_RevertWhen_ERC4626RatioNodeInitialRatioIsZero() external givenInvalidInputs {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory erc4626RatioNode =
            _createValidERC4626RatioNode(0, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, _createValidChainlinkNode(18, 18), erc4626RatioNode);
    }

    function test_RevertWhen_ERC4626RatioNodeInitialTimestampIsGreaterThanBlockTimestamp() external givenInvalidInputs {
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode(
            DEFAULT_INITIAL_RATIO, block.timestamp + 1, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, _createValidChainlinkNode(18, 18), erc4626RatioNode);
    }

    function test_RevertWhen_ERC4626RatioNodeMaxYearlyGrowthRatioWadIsZero() external givenInvalidInputs {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, 0);

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new AltoCappedChainlinkOracle(OWNER, _createValidChainlinkNode(18, 18), erc4626RatioNode);
    }

    function test_WhenValidInputsAreProvided() external givenValidInputs {
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 18);
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();

        vm.expectEmit(true, true, true, true);
        emit IAltoCappedChainlinkOracleEvents.SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0, 0), chainlinkNode
        );

        vm.expectEmit(true, true, true, true);
        emit IAltoCappedChainlinkOracleEvents.SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), erc4626RatioNode);

        AltoCappedChainlinkOracle oracle = new AltoCappedChainlinkOracle(OWNER, chainlinkNode, erc4626RatioNode);

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
        assertEq(outDecimals, 18);
        assertEq(feedDecimals, 8);

        (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, DEFAULT_INITIAL_RATIO);
        uint256 expectedTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        assertEq(initialTimestamp, expectedTimestamp);
        assertEq(maxYearlyGrowthRatioWad, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        assertEq(oracle.owner(), OWNER);
    }
}
