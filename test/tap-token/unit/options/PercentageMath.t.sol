// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import {PercentageMath} from 'tap-token/utils/PercentageMath.sol';

contract PercentageMathTest is Test {
    using PercentageMath for uint256;

  uint256 constant PERCENTAGE_FACTOR = 1e4;
  uint256 constant HALF_PERCENTAGE_FACTOR = 0.5e4;


  function test_percentMul_fuzz(uint256 value, uint256 percentage) public {
    if (
      (percentage == 0 ||
        (value > (type(uint256).max - HALF_PERCENTAGE_FACTOR) / percentage) == false) == false
    ) {
      vm.expectRevert();
      value.percentMul(percentage);
    } else {
      assertEq(
        value.percentMul(percentage),
        ((value * percentage) + HALF_PERCENTAGE_FACTOR) / (PERCENTAGE_FACTOR)
      );
    }
  }

  function test_percentMul() public pure {
    uint256 manualTestOne = 1e18;
    uint256 manualTestTwo = 14.2515e18;
    uint256 manualTestThree = 9087312e27;

    assertEq(manualTestOne.percentMul(50_00), 0.5e18);
    assertEq(manualTestTwo.percentMul(74_42), 10.605966300000000000e18);
    assertEq(manualTestThree.percentMul(13_33), 1211338689600000000000000000000000);
  }
}