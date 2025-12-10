// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAltoLeverageSwapper, SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AltoSwapper
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This contract is used to swap tokens in AltoLeverage contract during levarage and deleverage
/// @dev Contracts using this swapper have to handle potential reeentrancy protection caused by swap function by themselves
contract AltoLeverageSwapper is IAltoLeverageSwapper, Ownable {
    using SafeERC20 for IERC20;

    /// @notice 0x Allowance holder contract
    address public immutable SWAP_TARGET;

    /// @inheritdoc IAltoLeverageSwapper
    mapping(address => bool) public isWhitelisted;

    /// @notice constructor
    /// @param _owner the owner of the contract
    /// @param _swapTarget the address of the SWAP_TARGET
    constructor(address _owner, address _swapTarget) Ownable(_owner) {
        if (_swapTarget == address(0)) revert AltoLeverageSwapperInvalidInput();
        SWAP_TARGET = _swapTarget;
    }

    /// @inheritdoc IAltoLeverageSwapper
    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        if (isWhitelisted[_address] == _isWhitelisted) revert AltoLeverageSwapperInvalidInput();

        isWhitelisted[_address] = _isWhitelisted;
        emit SetWhitelisted(_address, _isWhitelisted);
    }

    /// @inheritdoc IAltoLeverageSwapper
    function swap(address sellToken, address buyToken, uint256 amountIn, bytes calldata swapParams)
        public
        payable
        returns (uint256)
    {
        if (!isWhitelisted[msg.sender]) {
            revert AltoLeverageSwapperSenderNotValid(msg.sender);
        }

        SwapParams memory params = abi.decode(swapParams, (SwapParams));

        // pull tokens from AltoLeverage contract to this contract
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(sellToken).forceApprove(SWAP_TARGET, amountIn);

        uint256 sellTokenBalanceBefore = IERC20(sellToken).balanceOf(address(this)) - amountIn;
        uint256 buyTokenBalanceBefore = IERC20(buyToken).balanceOf(address(this));

        (bool success,) = SWAP_TARGET.call(params.swapData);
        if (!success) revert AltoLeverageSwapperSwapFailed();

        IERC20(sellToken).forceApprove(SWAP_TARGET, 0);

        uint256 buyTokenBalanceReceived = IERC20(buyToken).balanceOf(address(this)) - buyTokenBalanceBefore;
        uint256 sellTokenBalanceLeftover = IERC20(sellToken).balanceOf(address(this)) - sellTokenBalanceBefore;

        if (buyTokenBalanceReceived < params.minAmountOut) {
            revert AltoLeverageSwapperMinAmountOutNotMet(params.minAmountOut, buyTokenBalanceReceived);
        }

        // transfer any leftover sell tokens to the sender
        if (sellTokenBalanceLeftover > 0) {
            IERC20(sellToken).safeTransfer(msg.sender, sellTokenBalanceLeftover);
        }

        if (buyTokenBalanceReceived > 0) {
            // Transfer the bought tokens to the sender
            IERC20(buyToken).safeTransfer(msg.sender, buyTokenBalanceReceived);
        }

        emit Swap(sellToken, buyToken, amountIn, buyTokenBalanceReceived, sellTokenBalanceLeftover);

        return buyTokenBalanceReceived;
    }
}
