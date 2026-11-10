// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoChainlinkERC4626RatioMultiplierOracleCommon} from "./AltoChainlinkERC4626RatioMultiplierOracleCommon.t.sol";
import {
    AltoChainlinkERC4626RatioMultiplierOracle
} from "@alto/oracles/AltoChainlinkERC4626RatioMultiplierOracle/AltoChainlinkERC4626RatioMultiplierOracle.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ERC4626RatioNode, ChainlinkNode, MultiplierNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract AltoChainlinkERC4626RatioMultiplierOracleGetPrice is AltoChainlinkERC4626RatioMultiplierOracleCommon {
    AltoChainlinkERC4626RatioMultiplierOracle oracle;

    function setUp() public override {
        super.setUp();
        oracle = _deployOracle();
    }

    modifier whenChainlinkFeedReturnsInvalidRate() {
        _;
    }

    modifier whenChainlinkPriceIsZero() {
        _;
    }

    modifier whenPriceIsWithinERC4626MaxAllowedGrowth() {
        _;
    }

    modifier whenPriceExceedsERC4626MaxAllowedGrowth() {
        _;
    }

    function test_RevertWhen_ChainlinkFeedIsStale() external whenChainlinkFeedReturnsInvalidRate {
        vm.warp(block.timestamp + DEFAULT_STALE_PERIOD + 2);
        uint256 staleUpdatedAt = block.timestamp - DEFAULT_STALE_PERIOD - 1;
        vm.mockCall(
            address(mockFeed1),
            abi.encodeWithSelector(mockFeed1.latestRoundData.selector),
            abi.encode(uint80(1), int256(100000000), staleUpdatedAt, staleUpdatedAt, uint80(1))
        );

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidRate.selector);
        oracle.getPrice();
    }

    function test_WhenChainlinkPriceIsZero() external whenChainlinkPriceIsZero {
        // Mock chainlink to return answer = 0 which produces a zero intermediate price
        // readLatestRatio(0, ...) returns 0, readMultipliedInput(0, ...) returns 0
        vm.mockCall(
            address(mockFeed1),
            abi.encodeWithSelector(mockFeed1.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), block.timestamp, block.timestamp, uint80(1))
        );

        // Chainlink module reverts on ratio <= 0
        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidRate.selector);
        oracle.getPrice();
    }

    function test_WhenPriceIsWithinMaxAllowedGrowth() external whenPriceIsWithinERC4626MaxAllowedGrowth {
        // MockChainlinkFeed returns 1e8 with 8 decimals (price = 1.0)
        // With inDecimals=18, outDecimals=18: chainlink output = 1e18
        // ERC4626 ratio: initialRatio=1e18, 1 hour elapsed, 10% yearly → maxRatio ≈ 1e18 + tiny amount
        // Chainlink output of 1e18 is within max → passes through uncapped
        // Multiplier of 10 → final = 1e18 * 10 = 1e19
        uint256 price = oracle.getPrice();
        assertEq(price, 1e18 * DEFAULT_MULTIPLIER);
    }

    function test_WhenPriceExceedsMaxAllowedGrowth() external whenPriceExceedsERC4626MaxAllowedGrowth {
        // Deploy oracle where initialRatio is much lower than chainlink output
        // so the chainlink price gets capped by erc4626 ratio
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory lowCapNode = _createValidERC4626RatioNode(
            0.5 ether, // initialRatio = 0.5e18 (much lower than the 1e18 chainlink returns)
            pastTimestamp,
            DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 18);
        MultiplierNode memory multiplierNode = _createValidMultiplierNode();

        AltoChainlinkERC4626RatioMultiplierOracle cappedOracle =
            new AltoChainlinkERC4626RatioMultiplierOracle(OWNER, chainlinkNode, lowCapNode, multiplierNode);

        uint256 price = cappedOracle.getPrice();

        // Chainlink returns 1e18, but max ratio ≈ 0.5e18 + (0.5e18 * 0.1e18 * 3600) / (1e18 * 365.2425 days)
        // ≈ 0.5e18 + negligible ≈ 0.5e18
        // So capped price < 1e18, and final = cappedPrice * 10
        uint256 uncappedPrice = 1e18 * DEFAULT_MULTIPLIER;
        assertLt(price, uncappedPrice);
        assertGt(price, 0);

        // The capped price should be roughly 0.5e18 * 10 = 5e18
        assertApproxEqRel(price, 0.5e18 * DEFAULT_MULTIPLIER, 1e15);
    }
}
