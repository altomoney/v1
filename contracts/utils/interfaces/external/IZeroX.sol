// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice swaps a token for another, using 0x as a swap aggregator
/// @dev All of the parameters below are provided by the API response.
/// @param sellToken the token to sell
/// @param buyToken the token to buy
/// @param swapTarget the 0x swap proxy
/// @param swapCallData the swap call data. Either 0x or 1inch
/// @return amountOut the amount of buyToken bought
struct SZeroXSwapData {
    IERC20 sellToken;
    IERC20 buyToken;
    address payable swapTarget;
    bytes swapCallData;
}
