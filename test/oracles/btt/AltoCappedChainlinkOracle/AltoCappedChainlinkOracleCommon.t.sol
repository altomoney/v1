// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoCappedChainlinkOracle} from "@alto/oracles/AltoCappedChainlinkOracle/AltoCappedChainlinkOracle.sol";
import {MockChainlinkFeed} from "../mocks/MockChainlinkFeed.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoCappedChainlinkOracleCommon is Test {
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);

    MockChainlinkFeed mockFeed1;
    MockChainlinkFeed mockFeed2;

    uint32 constant DEFAULT_STALE_PERIOD = 1 days;
    uint256 constant DEFAULT_INITIAL_RATIO = 1 ether;
    uint256 constant DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD = 0.1 ether; // 10% yearly growth

    function setUp() public virtual {
        mockFeed1 = new MockChainlinkFeed();
        mockFeed2 = new MockChainlinkFeed();
    }

    function _createValidChainlinkNode(uint8 inDecimals, uint8 outDecimals)
        internal
        view
        returns (ChainlinkNode memory)
    {
        return ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed1)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: inDecimals,
            outDecimals: outDecimals,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
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
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 8
        });
    }

    function _createValidERC4626RatioNode(
        uint256 initialRatio,
        uint256 initialTimestamp,
        uint256 maxYearlyGrowthRatioWad
    ) internal pure returns (ERC4626RatioNode memory) {
        return ERC4626RatioNode({
            initialRatio: initialRatio,
            initialTimestamp: initialTimestamp,
            maxYearlyGrowthRatioWad: maxYearlyGrowthRatioWad
        });
    }

    function _createValidERC4626RatioNode() internal view returns (ERC4626RatioNode memory) {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        return _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);
    }

    function _deployOracle() internal returns (AltoCappedChainlinkOracle) {
        return new AltoCappedChainlinkOracle(OWNER, _createValidChainlinkNode(18, 18), _createValidERC4626RatioNode());
    }
}
