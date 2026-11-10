// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockSwapper {
    using SafeERC20 for IERC20;

    function swap(bytes memory swapData) external returns (uint256) {
        (address sellToken, uint256 amountIn, address buyToken, uint256 minAmountOut) =
            abi.decode(swapData, (address, uint256, address, uint256));
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);

        IERC20(buyToken).safeTransfer(msg.sender, minAmountOut);

        return minAmountOut;
    }
}
