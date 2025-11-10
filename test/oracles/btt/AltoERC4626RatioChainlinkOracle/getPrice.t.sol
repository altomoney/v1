// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoERC4626RatioChainlinkOracleCommon} from "./AltoERC4626RatioChainlinkOracleCommon.t.sol";
import {MockAltoERC4626RatioChainlinkOracle} from "../mocks/MockAltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract AltoERC4626RatioChainlinkOracleGetPrice is AltoERC4626RatioChainlinkOracleCommon {
    MockAltoERC4626RatioChainlinkOracle oracle;

    function setUp() public override {
        super.setUp();
        ERC4626RatioNode memory erc4626RatioNode = _createValidERC4626RatioNode();
        ChainlinkNode memory chainlinkNode = _createValidChainlinkNode(18, 36);
        oracle = new MockAltoERC4626RatioChainlinkOracle(OWNER, erc4626RatioNode, chainlinkNode, 1.1 ether);
    }

    modifier givenRatioIsZero() {
        oracle.setRatio(0);
        _;
    }

    modifier givenRatioIsWithinMaxAllowedGrowth() {
        oracle.setRatio(1.05 ether);
        _;
    }

    modifier givenRatioExceedsMaxAllowedGrowth() {
        oracle.setRatio(1.2 ether);
        _;
    }

    function test_WhenRatioIsZero() external givenRatioIsZero {
        uint256 price = oracle.getPrice();
        assertEq(price, 0);
    }

    function test_WhenRatioIsWithinMaxAllowedGrowth() external givenRatioIsWithinMaxAllowedGrowth {
        vm.warp(block.timestamp + 365 days);
        uint256 price = oracle.getPrice();

        uint256 expectedPrice = 1.05 * 10 ** 36;
        assertEq(price, expectedPrice);
    }

    function test_WhenRatioExceedsMaxAllowedGrowth() external givenRatioExceedsMaxAllowedGrowth {
        vm.warp(block.timestamp + 365 days);
        // Mock returns 1.2 ether, but max allowed growth after 1 year with 10% yearly growth
        // Max ratio = initialRatio + (initialRatio * maxYearlyGrowthRatioWad * timePassed) / (MATH_PRECISION * SECONDS_PER_YEAR)
        // = 1e18 + (1e18 * 0.1e18 * 365 days) / (1e18 * 365.2425 days)
        // = 1e18 + (0.1e18 * 365 days) / 365.2425 days
        // ≈ 1e18 + 0.1e18 * 0.9993
        // ≈ 1.09993e18
        // Since mock returns 1.2e18, it should be capped to ~1.09993e18
        uint256 price = oracle.getPrice();

        uint256 uncappedPrice = 1.2 * 10 ** 36;
        assertLt(price, uncappedPrice);

        // it should return price in chainlinkNode.outDecimals (36 decimals)
        assertGt(price, 0);

        assertApproxEqRel(price, 1.09993e36, 1e15);
    }
}
