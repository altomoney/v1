// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoCappedChainlinkOracleCommon} from "./AltoCappedChainlinkOracleCommon.t.sol";
import {AltoCappedChainlinkOracle} from "@alto/oracles/AltoCappedChainlinkOracle/AltoCappedChainlinkOracle.sol";
import {MockChainlinkFeed} from "../mocks/MockChainlinkFeed.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoCappedChainlinkOracleGetPrice is AltoCappedChainlinkOracleCommon {
    AltoCappedChainlinkOracle oracle;

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

    function test_RevertWhen_ChainlinkPriceIsZero() external whenChainlinkPriceIsZero {
        vm.mockCall(
            address(mockFeed1),
            abi.encodeWithSelector(mockFeed1.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), block.timestamp, block.timestamp, uint80(1))
        );

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidRate.selector);
        oracle.getPrice();
    }

    function test_WhenPriceIsWithinMaxAllowedGrowth() external whenPriceIsWithinERC4626MaxAllowedGrowth {
        // MockChainlinkFeed returns 1e8 with 8 decimals (price = 1.0)
        // With inDecimals=18, outDecimals=18: chainlink output = 1e18
        // ERC4626 ratio: initialRatio=1e18, 1 hour elapsed, 10% yearly → maxRatio ≈ 1e18 + tiny amount
        // Chainlink output of 1e18 is within max → passes through uncapped
        uint256 price = oracle.getPrice();
        assertEq(price, 1e18);
    }

    function test_WhenPriceExceedsMaxAllowedGrowth() external whenPriceExceedsERC4626MaxAllowedGrowth {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory lowCapNode = _createValidERC4626RatioNode(
            0.5 ether, // initialRatio = 0.5e18 (much lower than the 1e18 chainlink returns)
            pastTimestamp,
            DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 18);

        AltoCappedChainlinkOracle cappedOracle = new AltoCappedChainlinkOracle(OWNER, chainlinkNode, lowCapNode);

        uint256 price = cappedOracle.getPrice();

        uint256 uncappedPrice = 1e18;
        assertLt(price, uncappedPrice);
        assertGt(price, 0);

        // The capped price should be roughly 0.5e18
        assertApproxEqRel(price, 0.5e18, 1e15);
    }

    function test_WhenOutDecimalsIs36_PriceScalesCorrectly() external {
        // Simulate the actual reUSD deployment config: 18-decimal feed, outDecimals=36
        address mockFeed18Dec = address(new MockChainlinkFeed());

        // Override to behave like the Re adapter: 18 decimals, answer = 1.05e18
        int256 navAnswer = 1.05 ether;
        vm.mockCall(
            mockFeed18Dec,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(uint8(18))
        );
        vm.mockCall(
            mockFeed18Dec,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), navAnswer, block.timestamp, block.timestamp, uint80(1))
        );

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(mockFeed18Dec),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 18
        });

        // initialRatio in 36 decimals, set above the feed price so cap doesn't bind
        uint256 initialRatio36 = uint256(navAnswer) * 1e18 * 1015 / 1000;
        ERC4626RatioNode memory ratioNode =
            _createValidERC4626RatioNode(initialRatio36, block.timestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        AltoCappedChainlinkOracle oracle36 = new AltoCappedChainlinkOracle(OWNER, chainlinkNode, ratioNode);

        uint256 price = oracle36.getPrice();

        // readChainlinkFeed(1e18, {in=18, out=36, feed=18}) = 1e18 * 1.05e18 * 1e36 / (1e18 * 1e18) = 1.05e36
        uint256 expected = uint256(navAnswer) * 1e18;
        assertEq(price, expected, "36-decimal scaling should produce nav * 1e18");
    }

    function test_WhenOutDecimalsIs36_CapBinds() external {
        address mockFeed18Dec = address(new MockChainlinkFeed());

        int256 navAnswer = 1.05 ether;
        vm.mockCall(
            mockFeed18Dec,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(uint8(18))
        );
        vm.mockCall(
            mockFeed18Dec,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), navAnswer, block.timestamp, block.timestamp, uint80(1))
        );

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(mockFeed18Dec),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 36,
            direction: ConversionDirection.IN_TO_OUT,
            feedDecimals: 18
        });

        // Set initialRatio well below chainlink output so cap binds
        uint256 lowInitialRatio36 = 0.5 ether * 1e18; // 0.5e36
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory ratioNode =
            _createValidERC4626RatioNode(lowInitialRatio36, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        AltoCappedChainlinkOracle oracle36 = new AltoCappedChainlinkOracle(OWNER, chainlinkNode, ratioNode);

        uint256 price = oracle36.getPrice();

        uint256 uncappedPrice = uint256(navAnswer) * 1e18; // 1.05e36
        assertLt(price, uncappedPrice, "Price should be capped below chainlink output");
        assertApproxEqRel(price, lowInitialRatio36, 1e15, "Capped price should be close to initialRatio");
    }
}
