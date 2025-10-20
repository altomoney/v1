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
    /// @param sellToken the token to sell
    /// @param buyToken the token to buy
    /// @param amountIn the amount of sellToken to sell
    /// @param swapParams ABI-encoded swap parameter (see `SwapParams` struct for details)
    /// @return amountOut the amount of buyToken bought
    /// @dev IMPORTANT:This function has to implement "minAmountOut" check using data proovided by `swapParams`
    function swap(address sellToken, address buyToken, uint256 amountIn, bytes calldata swapParams)
        external
        payable
        returns (uint256 amountOut);
}
