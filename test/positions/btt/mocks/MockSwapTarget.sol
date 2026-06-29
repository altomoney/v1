// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";

/// @notice Configurable swap target used by position swap legs.
contract MockSwapTarget {
    using SafeERC20 for IERC20;

    bool public shouldFail;
    uint256 public fixedOutput;

    uint256 public swapCallCount;
    address public lastSellToken;
    address public lastBuyToken;
    uint256 public lastAmountIn;

    /// @notice Configures swap revert behavior and buy-token output (`0` = 1:1 with `amountIn`).
    function setSwapOutcome(bool shouldRevert_, uint256 buyAmountOut_) external {
        shouldFail = shouldRevert_;
        fixedOutput = buyAmountOut_;
    }

    function swap(address sellToken, address buyToken, uint256) external {
        swapCallCount++;
        lastSellToken = sellToken;
        lastBuyToken = buyToken;

        uint256 amountIn = IERC20(sellToken).allowance(msg.sender, address(this));
        lastAmountIn = amountIn;
        if (amountIn == 0) return;

        if (shouldFail) revert();

        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 amountOut = fixedOutput > 0 ? fixedOutput : amountIn;
        if (amountOut > 0) {
            ERC20MockMintable(buyToken).mint(msg.sender, amountOut);
        }
    }
}
