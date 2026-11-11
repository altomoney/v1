// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ModuleLinearDiscount, SECONDS_PER_YEAR} from "@alto/oracles/modules/ModuleLinearDiscount.sol";
import {LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @notice Test harness exposing the internal validator
contract ModuleLinearDiscountHarness is ModuleLinearDiscount {
    function validate(LinearDiscountNode memory config) external view {
        _validateLinearDiscountParams(config);
    }
}

/// @notice Minimal PT mock returning a configurable expiry
contract MockPT {
    uint256 public expiry;

    constructor(uint256 _expiry) {
        expiry = _expiry;
    }
}

contract ModuleLinearDiscountTest is Test {
    ModuleLinearDiscountHarness module;

    function setUp() public {
        module = new ModuleLinearDiscountHarness();
    }

    function _node(uint256 maturity, uint256 rate, uint8 inDec, uint8 outDec)
        internal
        pure
        returns (LinearDiscountNode memory)
    {
        return LinearDiscountNode({
            ptToken: address(1), maturity: maturity, baseDiscountPerYear: rate, inDecimals: inDec, outDecimals: outDec
        });
    }

    function _validNode(uint256 maturity, uint256 rate, uint8 inDec, uint8 outDec)
        internal
        returns (LinearDiscountNode memory)
    {
        address pt = address(new MockPT(maturity));
        return LinearDiscountNode({
            ptToken: pt, maturity: maturity, baseDiscountPerYear: rate, inDecimals: inDec, outDecimals: outDec
        });
    }

    // Both at-maturity and post-maturity map timeLeft to 0, so discount = 0 and
    // the full quoteAmount is returned (only decimal scaling applies).
    function testAtAndPostMaturity(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        uint256 maturity = SECONDS_PER_YEAR / 2;
        vm.warp(maturity);
        // At maturity: timeLeft = 0 => discount = 0
        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity, 1e18, 18, 18)), quoteAmount);

        // Post maturity: discount = 0
        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity - 1, 1e18, 18, 18)), quoteAmount);
    }

    // 100% yearly rate with exactly 1 year remaining → discount = 1e18 → discountFactor = 0 → returns 0
    function testMaxRateFullYear(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR;
        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity, 1e18, 18, 18)), 0);
    }

    // 100% yearly rate, 6 months remaining:
    //   discount    = (SECONDS_PER_YEAR/2) * 1e18 / SECONDS_PER_YEAR = 0.5e18
    //   discountFactor = 0.5e18
    //   result      = quoteAmount * 0.5e18 * 1e18 / (1e18 * 1e18) = quoteAmount / 2
    function testHalfYearFullRate(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        uint256 secsPerYear = SECONDS_PER_YEAR;
        uint256 maturity = block.timestamp + secsPerYear / 2;
        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity, 1e18, 18, 18)), quoteAmount / 2);
    }

    // 50% yearly rate, 6 months remaining:
    //   discount    = (SECONDS_PER_YEAR/2) * 0.5e18 / SECONDS_PER_YEAR = 0.25e18
    //   discountFactor = 0.75e18
    //   result      = quoteAmount * 0.75e18 * 1e18 / (1e18 * 1e18) = quoteAmount * 3 / 4
    function testHalfYearHalfRate(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        uint256 secsPerYear = SECONDS_PER_YEAR;
        uint256 maturity = block.timestamp + secsPerYear / 2;
        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity, 0.5e18, 18, 18)), quoteAmount * 3 / 4);
    }

    // Zero quoteAmount always returns 0 regardless of discount or decimals
    function testZeroQuoteAmount() public view {
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR / 2;
        assertEq(module.readLinearDiscount(0, _node(maturity, 0.5e18, 18, 18)), 0);
    }

    // Using post-maturity to isolate scaling: discountFactor = 1e18
    // result = quoteAmount * 1e18 * powOut / (1e18 * powIn) = quoteAmount * powOut / powIn

    // Upscale 18 → 36: 1e18 token unit becomes 1e36 in output precision
    function testUpscaleDecimals(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        assertEq(module.readLinearDiscount(quoteAmount, _node(block.timestamp, 0, 18, 36)), quoteAmount * 1e36 / 1e18);
    }

    // Downscale 18 → 8: 1e18 token unit becomes 1e8 in output precision
    function testDownscaleDecimals(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        assertEq(module.readLinearDiscount(quoteAmount, _node(block.timestamp, 0, 18, 8)), quoteAmount * 1e8 / 1e18);
    }

    // Discount and decimal scaling combined:
    //   50% discount (half year at 100% rate), 18→8 scaling
    //   result = quoteAmount * 0.5e18 * 1e8 / (1e18 * 1e18) = quoteAmount * 5e7 / 1e18
    function testDiscountWithDecimalScaling(uint256 quoteAmount) public {
        quoteAmount = bound(quoteAmount, 0.00001e18, 1_000_000 * 10 ** 18);
        uint256 secsPerYear = SECONDS_PER_YEAR;
        uint256 maturity = block.timestamp + secsPerYear / 2;
        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity, 1e18, 18, 8)), quoteAmount * 5e7 / 1e18);
    }

    // The module should preserve small non-zero values until the final division.
    // Before the one-shot mulDiv fix, the intermediate floor in
    // discountFactor * 10^outDecimals / 1e18 would round to zero here.
    function testLowOutDecimalsSmallDiscountFactorDoesNotRoundToZeroEarly() public view {
        uint256 quoteAmount = 2_000e18;
        uint256 discountFactor = 5e9;
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR;
        uint256 rate = 1e18 - discountFactor;

        assertEq(module.readLinearDiscount(quoteAmount, _node(maturity, rate, 18, 8)), 1000);
    }

    // Discount > 1e18 triggers ModuleLinearDiscountInvalidRate.
    // Happens when timeLeft * baseDiscountPerYear > SECONDS_PER_YEAR * 1e18,
    // e.g. exactly 1 second beyond a full year at max rate.
    function testRevertWhen_DiscountOverflow() public {
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR + 1;
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidRate.selector);
        module.readLinearDiscount(1e18, _node(maturity, 1e18, 18, 18));
    }

    // The config-time validator must reject (timeLeft, rate) pairs that would later
    // brick readLinearDiscount via ModuleLinearDiscountInvalidRate. This locks in the
    // companion guard to testRevertWhen_DiscountOverflow at the configuration path.
    function test_RevertWhen_ConfigImpliesDiscountAboveOne() public {
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR + 1;
        LinearDiscountNode memory cfg = _validNode(maturity, 1e18, 18, 18);
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        module.validate(cfg);
    }

    // The exact boundary (timeLeft * rate == SECONDS_PER_YEAR * 1e18) must be allowed,
    // matching the runtime semantics where discount == 1e18 is permitted.
    function test_AllowsConfigAtFullYearMaxRateBoundary() public {
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR;
        LinearDiscountNode memory cfg = _validNode(maturity, 1e18, 18, 18);
        module.validate(cfg);
    }
}
