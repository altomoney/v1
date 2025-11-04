// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAltoLeverageSwapper, SwapParams} from "@alto/lending/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MaliciousERC20} from "./MaliciousERC20.sol";

struct MockSwapperData {
    address maliciousERC20;
    uint256 minAmountOut;
}

contract MockSwapper is IAltoLeverageSwapper, Ownable {
    mapping(address => bool) public isWhitelisted;

    constructor(address _owner) Ownable(_owner) {}

    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        isWhitelisted[_address] = _isWhitelisted;
    }

    function swap(address sellToken, address buyToken, uint256 amountIn, bytes calldata swapParams)
        public
        payable
        returns (uint256 amountOut)
    {
        MockSwapperData memory data = abi.decode(swapParams, (MockSwapperData));

        // Transfer tokens to this contract
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(sellToken).transferFrom(msg.sender, address(this), amountIn);

        MaliciousERC20(data.maliciousERC20).transfer(msg.sender, 1);

        // No need to implement minAmountOut check here as it is mock contract
        amountOut = data.minAmountOut;

        // Transfer the bought tokens to the sender
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(buyToken).transfer(msg.sender, amountOut);
    }
}
