// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Mock swap target used by WrapperToken swap BTT tests.
contract SwapTargetMock {
    bool public shouldRevert;
    bool public leaveSellLeftover;
    uint256 public sellAmountToTake;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function setLeaveSellLeftover(uint256 amountToTake) external {
        leaveSellLeftover = true;
        sellAmountToTake = amountToTake;
    }

    function resetBehavior() external {
        shouldRevert = false;
        leaveSellLeftover = false;
        sellAmountToTake = 0;
    }

    function executeSwap(address sellToken, address buyToken, uint256 amountIn, uint256 buyAmountOut) external {
        if (shouldRevert) revert();

        uint256 take = leaveSellLeftover ? sellAmountToTake : amountIn;
        IERC20(sellToken).transferFrom(msg.sender, address(this), take);
        IERC20(buyToken).transfer(msg.sender, buyAmountOut);
    }
}
