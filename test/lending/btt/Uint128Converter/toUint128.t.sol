// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Uint128ConverterMock} from "./Uint128ConverterMock.sol";
import {Uint128Converter} from "../../../../contracts/lending/libraries/Uint128Converter.sol";

contract ToUint128Test is Test {
    Uint128ConverterMock internal converter;

    function setUp() public {
        converter = new Uint128ConverterMock();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ToUint128_WhenXIsZero() public {
        // It should return zero
        uint128 result = converter.toUint128(0);
        assertEq(result, 0);
    }

    function test_ToUint128_WhenXEqualsOne() public {
        // It should return 1
        uint128 result = converter.toUint128(1);
        assertEq(result, 1);
    }

    function test_ToUint128_WhenXEqualsUint128Max() public {
        // It should return type(uint128).max
        uint256 maxUint128 = type(uint128).max;
        uint128 result = converter.toUint128(maxUint128);
        assertEq(result, type(uint128).max);
    }

    function testFuzz_ToUint128_WhenXIsWithinRange(uint128 x) public {
        // It should return the same value as uint128
        uint256 input = uint256(x);
        uint128 result = converter.toUint128(input);
        assertEq(result, x);
    }

    /*//////////////////////////////////////////////////////////////
                            REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_XEqualsUint128MaxPlusOne() public {
        // It should revert with MathUtilsMaxUint128Overflow
        uint256 overflowValue = uint256(type(uint128).max) + 1;

        vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
        converter.toUint128(overflowValue);
    }

    function test_RevertWhen_XEqualsUint256Max() public {
        // It should revert with MathUtilsMaxUint128Overflow
        uint256 maxUint256 = type(uint256).max;

        vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
        converter.toUint128(maxUint256);
    }

    function testFuzz_RevertWhen_XIsAboveRange(uint256 x) public {
        // It should revert with MathUtilsMaxUint128Overflow
        vm.assume(x > type(uint128).max);

        vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
        converter.toUint128(x);
    }

    /*//////////////////////////////////////////////////////////////
                        BOUNDARY VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ToUint128_BoundaryValues() public {
        // Test several boundary values
        uint256[] memory boundaryValues = new uint256[](5);
        boundaryValues[0] = 0;
        boundaryValues[1] = 1;
        boundaryValues[2] = type(uint64).max;
        boundaryValues[3] = type(uint128).max - 1;
        boundaryValues[4] = type(uint128).max;

        for (uint256 i = 0; i < boundaryValues.length; i++) {
            uint128 result = converter.toUint128(boundaryValues[i]);
            assertEq(result, uint128(boundaryValues[i]));
        }
    }

    function test_RevertWhen_BoundaryOverflowValues() public {
        // Test values that should cause overflow
        uint256[] memory overflowValues = new uint256[](3);
        overflowValues[0] = uint256(type(uint128).max) + 1;
        overflowValues[1] = uint256(type(uint128).max) + 100;
        overflowValues[2] = type(uint256).max;

        for (uint256 i = 0; i < overflowValues.length; i++) {
            vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
            converter.toUint128(overflowValues[i]);
        }
    }
}
