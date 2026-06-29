// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SwapPositionLib
/// @notice Internal swap helper for swapping tokens through an approved target
library SwapPositionLib {
    using SafeERC20 for IERC20;

    /// @notice Thrown when the swap fails
    error SwapPositionSwapFailed();
    /// @notice Thrown when the minimum amount out is not met
    error SwapPositionMinAmountOutNotMet(uint256 minAmountOut, uint256 received);

    /// @notice Executes a swap through an approved target and returns the buy-token balance delta.
    /// @dev This function assumes that there will not be sell token delta and swapData is generated in such a way that exact amountIn is utilized
    /// @param position The address of the position to swap tokens for
    /// @param sellToken The address of the token to sell
    /// @param buyToken The address of the token to buy
    /// @param amountIn The amount of tokens to sell
    /// @param swapTarget The address of the target to swap tokens through
    /// @param swapData The data to pass to the target
    /// @param minAmountOut The minimum amount of tokens to buy
    /// @return amountOut The amount of tokens bought
    function swap(
        address position,
        address sellToken,
        address buyToken,
        uint256 amountIn,
        address swapTarget,
        bytes memory swapData,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IERC20(sellToken).forceApprove(swapTarget, amountIn);

        uint256 buyTokenBalanceBefore = IERC20(buyToken).balanceOf(position);

        (bool success,) = swapTarget.call(swapData);
        if (!success) revert SwapPositionSwapFailed();

        IERC20(sellToken).forceApprove(swapTarget, 0);

        amountOut = IERC20(buyToken).balanceOf(position) - buyTokenBalanceBefore;

        if (amountOut < minAmountOut) {
            revert SwapPositionMinAmountOutNotMet(minAmountOut, amountOut);
        }
    }
}
