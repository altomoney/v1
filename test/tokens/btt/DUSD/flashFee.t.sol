// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IDUSD, FlashFee} from "@alto/tokens/interfaces/IDUSD.sol";

contract FlashFeeTest is DUSDCommon {
    uint256 constant TEST_AMOUNT = 1000e18;
    uint256 constant FLASH_MINT_CAP = 10000e18;
    uint128 constant MIN_FLASH_FEE_0_1_PERCENT = 0.001 ether; // 0.1% (1 ether = 100%)
    uint128 constant MAX_FLASH_FEE_1_PERCENT = 0.01 ether; // 1% (1 ether = 100%)
    uint128 constant FLAT_FLASH_FEE_0_5_PERCENT = 0.005 ether; // 0.5% (1 ether = 100%)

    modifier givenFlashMintCapIsZero() {
        // Default state: flashMintCap = 0
        _;
    }

    modifier givenFlashMintCapIsNonZero() {
        vm.prank(OWNER);
        dusd.setFlashMintCap(FLASH_MINT_CAP);
        _;
    }

    modifier givenFlashFeeIsZero() {
        // Default state: flashFee struct is zero
        _;
    }

    modifier givenFlashFeeMinEqualsMax() {
        vm.startPrank(OWNER);
        dusd.setFlashFee(FlashFee({minFlashFee: FLAT_FLASH_FEE_0_5_PERCENT, maxFlashFee: FLAT_FLASH_FEE_0_5_PERCENT}));
        vm.stopPrank();
        _;
    }

    modifier givenFlashFeeMaxGreaterThanMin() {
        vm.startPrank(OWNER);
        dusd.setFlashFee(FlashFee({minFlashFee: MIN_FLASH_FEE_0_1_PERCENT, maxFlashFee: MAX_FLASH_FEE_1_PERCENT}));
        vm.stopPrank();
        _;
    }

    modifier givenFlashFeeMinGreaterThanMax() {
        vm.startPrank(OWNER);
        dusd.setFlashFee(FlashFee({minFlashFee: MAX_FLASH_FEE_1_PERCENT, maxFlashFee: MIN_FLASH_FEE_0_1_PERCENT}));
        vm.stopPrank();
        _;
    }

    function test_WhenFlashFeeIsZero_AmountIsAnything(uint256 amount)
        external
        givenFlashFeeIsZero
        givenFlashMintCapIsNonZero
    {
        amount = bound(amount, 0, FLASH_MINT_CAP);
        assertEq(dusd.flashFee(address(dusd), 0), 0);
        assertEq(dusd.flashFee(address(dusd), amount), 0);
        assertEq(dusd.flashFee(address(dusd), amount / 2), 0);
    }

    function test_WhenFlashMintCapIsZero_AmountIsZero() external givenFlashMintCapIsZero {
        assertEq(dusd.flashFee(address(dusd), 0), 0);
    }

    function test_RevertWhen_FlashMintCapIsZero_AmountIsGreaterThanZero(uint256 amount)
        external
        givenFlashMintCapIsZero
    {
        amount = bound(amount, 1, 1000 ether);
        vm.expectRevert(IDUSD.DUSDExceededFlashMintCap.selector);
        dusd.flashFee(address(dusd), amount);
    }

    function test_RevertWhen_AmountExceedsFlashMintCap() external givenFlashMintCapIsNonZero {
        vm.expectRevert(IDUSD.DUSDExceededFlashMintCap.selector);
        dusd.flashFee(address(dusd), FLASH_MINT_CAP + 1);
    }

    function test_WhenMinEqualsMax_AmountIsZero() external givenFlashMintCapIsNonZero givenFlashFeeMinEqualsMax {
        assertEq(dusd.flashFee(address(dusd), 0), 0);
    }

    function test_WhenMinEqualsMax_AmountIsNonZero(uint256 amount)
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMinEqualsMax
    {
        // Ensure amount is between a minimum that yields non-zero fee and FLASH_MINT_CAP
        // Minimum amount needed: FLAT_FLASH_FEE_0_5_PERCENT * amount >= MATH_PRECISION
        // So: amount >= MATH_PRECISION / FLAT_FLASH_FEE_0_5_PERCENT
        uint256 minAmount = MATH_PRECISION / FLAT_FLASH_FEE_0_5_PERCENT;
        if (minAmount == 0 || minAmount > FLASH_MINT_CAP) {
            minAmount = 1;
        }
        amount = bound(amount, minAmount, FLASH_MINT_CAP);
        uint256 expectedFee = FixedPointMath.multiplyWithPrecisionUp(FLAT_FLASH_FEE_0_5_PERCENT, amount);
        assertEq(dusd.flashFee(address(dusd), amount), expectedFee);
        assertGt(expectedFee, 0);
        assertLt(expectedFee, amount);
    }

    function test_WhenMinEqualsMax_AmountIsDoubled(uint256 baseAmount)
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMinEqualsMax
    {
        baseAmount = bound(baseAmount, 1, FLASH_MINT_CAP / 2);
        uint256 doubledAmount = baseAmount * 2;
        uint256 baseFee = dusd.flashFee(address(dusd), baseAmount);
        uint256 doubledFee = dusd.flashFee(address(dusd), doubledAmount);
        assertApproxEqAbs(doubledFee, baseFee * 2, 1);
    }

    function test_WhenMinEqualsMax_AmountIsHalved(uint256 baseAmount)
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMinEqualsMax
    {
        baseAmount = bound(baseAmount, 2, FLASH_MINT_CAP);
        uint256 halvedAmount = baseAmount / 2;
        uint256 baseFee = dusd.flashFee(address(dusd), baseAmount);
        uint256 halvedFee = dusd.flashFee(address(dusd), halvedAmount);
        assertApproxEqAbs(halvedFee, baseFee / 2, 1);
    }

    function test_WhenMaxGreaterThanMin_AmountIsZero()
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMaxGreaterThanMin
    {
        uint256 fee = dusd.flashFee(address(dusd), 0);
        assertEq(fee, 0);
    }

    function test_WhenMaxGreaterThanMin_AmountEqualsFlashMintCap()
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMaxGreaterThanMin
    {
        uint256 fee = dusd.flashFee(address(dusd), FLASH_MINT_CAP);
        uint256 expectedFee = FixedPointMath.multiplyWithPrecisionUp(MAX_FLASH_FEE_1_PERCENT, FLASH_MINT_CAP);
        assertApproxEqAbs(fee, expectedFee, 1);
    }

    function test_WhenMaxGreaterThanMin_AmountIsBetweenZeroAndFlashMintCap()
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMaxGreaterThanMin
    {
        uint256 testAmount = FLASH_MINT_CAP / 2;
        uint256 fee = dusd.flashFee(address(dusd), testAmount);

        // Calculate expected fee: should be between min and max
        uint256 minFeeAmount = FixedPointMath.multiplyWithPrecisionUp(MIN_FLASH_FEE_0_1_PERCENT, testAmount);
        uint256 maxFeeAmount = FixedPointMath.multiplyWithPrecisionUp(MAX_FLASH_FEE_1_PERCENT, testAmount);
        uint256 expectedFee = (minFeeAmount + maxFeeAmount) / 2;

        assertGt(fee, minFeeAmount);
        assertLt(fee, maxFeeAmount);
        assertApproxEqAbs(fee, expectedFee, 1);
        assertGt(fee, 0);
    }

    function test_WhenMinGreaterThanMax_AmountIsZero()
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMinGreaterThanMax
    {
        uint256 fee = dusd.flashFee(address(dusd), 0);
        uint256 expectedFee = FixedPointMath.multiplyWithPrecisionUp(MAX_FLASH_FEE_1_PERCENT, 0);
        assertEq(fee, expectedFee);
        assertEq(fee, 0);
    }

    function test_WhenMinGreaterThanMax_AmountEqualsFlashMintCap()
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMinGreaterThanMax
    {
        uint256 fee = dusd.flashFee(address(dusd), FLASH_MINT_CAP);
        uint256 expectedFee = FixedPointMath.multiplyWithPrecisionUp(MIN_FLASH_FEE_0_1_PERCENT, FLASH_MINT_CAP);
        assertApproxEqAbs(fee, expectedFee, 1);
    }

    function test_WhenMinGreaterThanMax_AmountIsBetweenZeroAndFlashMintCap()
        external
        givenFlashMintCapIsNonZero
        givenFlashFeeMinGreaterThanMax
    {
        uint256 testAmount = FLASH_MINT_CAP / 2;
        uint256 fee = dusd.flashFee(address(dusd), testAmount);

        // Calculate expected fee: should be between max and min (decreasing)
        uint256 minFeeAmount = FixedPointMath.multiplyWithPrecisionUp(MIN_FLASH_FEE_0_1_PERCENT, testAmount);
        uint256 maxFeeAmount = FixedPointMath.multiplyWithPrecisionUp(MAX_FLASH_FEE_1_PERCENT, testAmount);
        uint256 expectedFee = (minFeeAmount + maxFeeAmount) / 2;

        assertApproxEqAbs(fee, expectedFee, 1);
        assertGt(fee, minFeeAmount);
        assertLt(fee, maxFeeAmount);
        assertGt(fee, 0);
    }
}
