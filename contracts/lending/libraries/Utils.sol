// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {
    error MathUtilsMaxUint128Overflow();
    
    function onlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0 && y != 0) || (x != 0 && y == 0);
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        if (x > type(uint128).max) {
            revert MathUtilsMaxUint128Overflow();
        }

        return uint128(x);
    }
}
