// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct SwapParams {
    /// @notice the minimum amount of buyToken to buy
    uint256 minAmountOut;
    /// @notice the swap calldata to pass to the swap target contract
    bytes swapData;
}

interface IAltoLeverageSwapper {
    /// @notice function that should swaps a token for another
    /// @param swapParams encoding of the minimum amount of buyToken to buy and
    ///                   the swapdata specific for the underlying implementation
    /// @param amountIn the amount of sellToken to sell
    /// @return amountOut the amount of buyToken bought
    function swap(bytes calldata swapParams, address sellToken, address buyToken, uint256 amountIn)
        external
        payable
        returns (uint256 amountOut);
}
