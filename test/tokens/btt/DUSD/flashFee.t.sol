// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";

contract FlashFeeTest is DUSDCommon {
    uint256 constant TEST_AMOUNT = 1000e18;
    uint256 constant FLASH_FEE_1_PERCENT = 0.01e18; // 1% in MATH_PRECISION
    uint256 constant FLASH_FEE_0_1_PERCENT = 0.001e18; // 0.1% in MATH_PRECISION

    modifier givenFlashFeeIsZero() {
        // Default state: flashFee = 0
        _;
    }

    modifier givenFlashFeeIsNonZero() {
        vm.startPrank(OWNER);
        dusd.setFlashFee(FLASH_FEE_1_PERCENT);
        vm.stopPrank();
        _;
    }

    function test_WhenFlashFeeIsZero_AmountIsAnything(uint256 amount) external givenFlashFeeIsZero {
        amount = bound(amount, 0, type(uint128).max);
        assertEq(dusd.flashFee(address(dusd), 0), 0);

        assertEq(dusd.flashFee(address(dusd), amount), 0);

        // Test with medium amount
        assertEq(dusd.flashFee(address(dusd), amount / 2), 0);
    }

    function test_WhenFlashFeeIsNonZero_AmountIsZero() external givenFlashFeeIsNonZero {
        assertEq(dusd.flashFee(address(dusd), 0), 0);
    }

    function test_WhenFlashFeeIsNonZero_AmountIsNonZero(uint256 amount) external givenFlashFeeIsNonZero {
        amount = bound(amount, 2, type(uint128).max);
        uint256 expectedFee = FixedPointMath.multiplyWithPrecisionUp(FLASH_FEE_1_PERCENT, amount);
        assertEq(dusd.flashFee(address(dusd), amount), expectedFee);

        assertGt(expectedFee, 0);
        assertLt(expectedFee, amount);
    }

    function test_WhenAmountIsDoubled(uint256 baseAmount) external givenFlashFeeIsNonZero {
        baseAmount = bound(baseAmount, 2, type(uint64).max);
        uint256 doubledAmount = baseAmount * 2;
        uint256 baseFee = dusd.flashFee(address(dusd), baseAmount);
        uint256 doubledFee = dusd.flashFee(address(dusd), doubledAmount);
        assertApproxEqAbs(doubledFee, baseFee * 2, 1);
    }

    function test_WhenAmountIsHalved(uint256 baseAmount) external givenFlashFeeIsNonZero {
        baseAmount = bound(baseAmount, 2, type(uint64).max);
        uint256 halvedAmount = baseAmount / 2;

        uint256 baseFee = dusd.flashFee(address(dusd), baseAmount);
        uint256 halvedFee = dusd.flashFee(address(dusd), halvedAmount);

        assertApproxEqAbs(halvedFee, baseFee / 2, 1);
    }

    function test_WhenFlashFeeIsDifferentPercentages(uint256 testAmount) external {
        testAmount = bound(testAmount, 2, type(uint128).max);

        vm.startPrank(OWNER);
        dusd.setFlashFee(FLASH_FEE_0_1_PERCENT);
        vm.stopPrank();
        uint256 fee0_1 = dusd.flashFee(address(dusd), testAmount);

        vm.startPrank(OWNER);
        dusd.setFlashFee(FLASH_FEE_1_PERCENT);
        vm.stopPrank();

        uint256 fee1 = dusd.flashFee(address(dusd), testAmount);
        uint256 expected1 = FixedPointMath.multiplyWithPrecisionUp(FLASH_FEE_1_PERCENT, testAmount);
        assertEq(fee1, expected1);

        assertApproxEqAbs(fee1, fee0_1 * 10, 10);
    }
}
