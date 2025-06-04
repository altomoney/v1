// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAltoLeverageSwapper {
    /// @notice function that should swaps a token for another
    /// @param swapData the swap data specific for the underlying implementation
    /// @param amountIn the amount of sellToken to sell
    /// @param minAmountOut the minimum amount of buyToken bought
    /// @return amountOut the amount of buyToken bought
    function swap(bytes calldata swapData, address sellToken, address buyToken, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        returns (uint256 amountOut);
}
