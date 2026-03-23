// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoERC4626RatioLinearDiscountOracleCommon} from "./AltoERC4626RatioLinearDiscountOracleCommon.t.sol";
import {MockAltoERC4626RatioLinearDiscountOracle} from "../mocks/MockAltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {SECONDS_PER_YEAR} from "@alto/oracles/modules/ModuleLinearDiscount.sol";

contract AltoERC4626RatioLinearDiscountOracleGetPrice is AltoERC4626RatioLinearDiscountOracleCommon {
    MockAltoERC4626RatioLinearDiscountOracle internal oracle;

    function setUp() public {
        vm.warp(1_700_000_000);

        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        LinearDiscountNode memory discountNode = _createValidLinearDiscountNode();
        oracle = new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.005 ether);
    }

    function _readERC4626RatioNode() private view returns (ERC4626RatioNode memory) {
        (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        return ERC4626RatioNode({
            initialRatio: initialRatio,
            initialTimestamp: initialTimestamp,
            maxYearlyGrowthRatioWad: maxYearlyGrowthRatioWad
        });
    }

    function _readLinearDiscountNode() private view returns (LinearDiscountNode memory) {
        (address ptToken, uint256 maturity, uint256 baseDiscountPerYear, uint8 inDecimals, uint8 outDecimals) =
            oracle.linearDiscountNode();
        return LinearDiscountNode({
            ptToken: ptToken,
            maturity: maturity,
            baseDiscountPerYear: baseDiscountPerYear,
            inDecimals: inDecimals,
            outDecimals: outDecimals
        });
    }

    // ===== Modifiers =====

    modifier givenRatioIsZero() {
        oracle.setRatio(0);
        _;
    }

    /// @dev Warp 30 days. At 10%/year growth, maxRatio ≈ 1.0082e18 after 30 days
    /// Ratio 1.005e18 is within cap. Maturity is ~90 days out, so ~60 days remain (meaningful discount).
    modifier givenRatioIsWithinMaxAllowedGrowth() {
        vm.warp(block.timestamp + 30 days);
        oracle.setRatio(1.005 ether);
        _;
    }

    /// @dev Only 1 hour has elapsed since initialTimestamp.
    /// maxRatio ≈ 1.0000114e18, so 1.5e18 is heavily capped.
    modifier givenRatioExceedsMaxAllowedGrowth() {
        oracle.setRatio(1.5 ether);
        _;
    }

    /// @dev Warp past the stored maturity so discount = 0
    modifier givenPTIsPostMaturity() {
        (, uint256 maturity,,,) = oracle.linearDiscountNode();
        vm.warp(maturity + 1);
        _;
    }

    function test_WhenRatioIsZero() external givenRatioIsZero {
        assertEq(oracle.getPrice(), 0);
    }

    function test_WhenRatioIsWithinMaxAllowedGrowth_GivenPreMaturity() external givenRatioIsWithinMaxAllowedGrowth {
        uint256 ratio = 1.005 ether;
        ERC4626RatioNode memory ratioNode = _readERC4626RatioNode();
        LinearDiscountNode memory discountNode = _readLinearDiscountNode();

        // it should not cap the ratio
        uint256 cappedRatio = oracle.readLatestRatio(ratio, ratioNode);
        assertEq(cappedRatio, ratio, "ratio should not be capped");

        // it should apply the linear discount to the ratio
        uint256 expectedPrice = oracle.readLinearDiscount(cappedRatio, discountNode);
        assertEq(oracle.getPrice(), expectedPrice);

        // it should return a price less than the undiscounted value
        uint256 undiscountedValue = ratio * 10 ** (DEFAULT_OUT_DECIMALS - DEFAULT_IN_DECIMALS);
        assertLt(expectedPrice, undiscountedValue, "pre-maturity price should be less than undiscounted");
    }

    function test_WhenRatioIsWithinMaxAllowedGrowth_GivenPostMaturity()
        external
        givenRatioIsWithinMaxAllowedGrowth
        givenPTIsPostMaturity
    {
        uint256 ratio = 1.005 ether;
        ERC4626RatioNode memory ratioNode = _readERC4626RatioNode();
        LinearDiscountNode memory discountNode = _readLinearDiscountNode();

        // it should not cap the ratio
        // After ~90 days at 10%/year: maxRatio ≈ 1.0246e18 > 1.005e18
        uint256 cappedRatio = oracle.readLatestRatio(ratio, ratioNode);
        assertEq(cappedRatio, ratio, "ratio should not be capped post-maturity");

        // it should apply no discount (post-maturity: timeLeft = 0)
        uint256 expectedPrice = oracle.readLinearDiscount(cappedRatio, discountNode);
        assertEq(oracle.getPrice(), expectedPrice);

        // it should return the ratio scaled to outDecimals
        uint256 scaledRatio = ratio * 10 ** (DEFAULT_OUT_DECIMALS - DEFAULT_IN_DECIMALS);
        assertEq(expectedPrice, scaledRatio, "post-maturity price should equal ratio scaled to outDecimals");
    }

    function test_WhenRatioExceedsMaxAllowedGrowth_GivenPreMaturity() external givenRatioExceedsMaxAllowedGrowth {
        uint256 rawRatio = 1.5 ether;
        ERC4626RatioNode memory ratioNode = _readERC4626RatioNode();
        LinearDiscountNode memory discountNode = _readLinearDiscountNode();

        // it should cap the ratio to max allowed growth
        uint256 cappedRatio = oracle.readLatestRatio(rawRatio, ratioNode);
        assertLt(cappedRatio, rawRatio, "ratio should be capped");

        // it should apply the linear discount to the capped ratio
        uint256 expectedPrice = oracle.readLinearDiscount(cappedRatio, discountNode);
        assertEq(oracle.getPrice(), expectedPrice);

        // it should return a price less than the uncapped undiscounted value
        uint256 uncappedScaled = rawRatio * 10 ** (DEFAULT_OUT_DECIMALS - DEFAULT_IN_DECIMALS);
        assertLt(expectedPrice, uncappedScaled, "price should be less than uncapped undiscounted");
        assertGt(expectedPrice, 0, "price should be positive");
    }

    function test_WhenRatioExceedsMaxAllowedGrowth_GivenPostMaturity()
        external
        givenRatioExceedsMaxAllowedGrowth
        givenPTIsPostMaturity
    {
        uint256 rawRatio = 1.5 ether;
        ERC4626RatioNode memory ratioNode = _readERC4626RatioNode();
        LinearDiscountNode memory discountNode = _readLinearDiscountNode();

        // it should cap the ratio to max allowed growth (cap is independent of maturity)
        uint256 cappedRatio = oracle.readLatestRatio(rawRatio, ratioNode);
        assertLt(cappedRatio, rawRatio, "ratio should be capped even post-maturity");

        // it should apply no discount to the capped ratio (timeLeft = 0)
        uint256 expectedPrice = oracle.readLinearDiscount(cappedRatio, discountNode);
        assertEq(oracle.getPrice(), expectedPrice);

        // it should return the capped ratio scaled to outDecimals
        uint256 cappedScaled = cappedRatio * 10 ** (DEFAULT_OUT_DECIMALS - DEFAULT_IN_DECIMALS);
        assertEq(expectedPrice, cappedScaled, "post-maturity price should be capped ratio in outDecimals");
    }
}
