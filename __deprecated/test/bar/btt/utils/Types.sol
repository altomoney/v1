// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

abstract contract Types {
    struct SSwapData {
        uint256 minAmountOut;
        SZeroXSwapData data;
    }

    struct SZeroXSwapData {
        address sellToken;
        address buyToken;
        address payable swapTarget;
        bytes swapCallData;
    }
}
