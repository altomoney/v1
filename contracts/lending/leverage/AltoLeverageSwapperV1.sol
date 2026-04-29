// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {
    IAltoLeverageSwapperV1,
    SwapParamsV1,
    IAltoLeverageSwapper
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AltoLeverageSwapperV1
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This contract is used to swap tokens in AltoLeverage contract during levarage and deleverage
/// @dev This contract uses whitelisted SWAP_TARGET instead of fixed address for the swap target
/// @dev Contracts using this swapper have to handle potential reeentrancy protection caused by swap function by themselves
contract AltoLeverageSwapperV1 is IAltoLeverageSwapperV1, Ownable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IAltoLeverageSwapperV1
    mapping(address => bool) public isValidSwapTarget;

    /// @inheritdoc IAltoLeverageSwapper
    mapping(address => bool) public isWhitelisted;

    /// @notice constructor
    /// @param _owner the owner of the contract
    constructor(address _owner, address[] memory validSwapTargets) Ownable(_owner) {
        for (uint256 i = 0; i < validSwapTargets.length; i++) {
            if (validSwapTargets[i] == address(0)) revert AltoLeverageSwapperInvalidInput();
            isValidSwapTarget[validSwapTargets[i]] = true;

            emit SetValidSwapTarget(validSwapTargets[i], true);
        }
    }

    /// @inheritdoc IAltoLeverageSwapper
    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        if (isWhitelisted[_address] == _isWhitelisted) revert AltoLeverageSwapperInvalidInput();

        isWhitelisted[_address] = _isWhitelisted;
        emit SetWhitelisted(_address, _isWhitelisted);
    }

    /// @inheritdoc IAltoLeverageSwapperV1
    function setValidSwapTarget(address _swapTarget, bool _isValid) external onlyOwner {
        if (isValidSwapTarget[_swapTarget] == _isValid) revert AltoLeverageSwapperInvalidInput();

        isValidSwapTarget[_swapTarget] = _isValid;
        emit SetValidSwapTarget(_swapTarget, _isValid);
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

        SwapParamsV1 memory params = abi.decode(swapParams, (SwapParamsV1));

        if (!isValidSwapTarget[params.swapTarget]) {
            revert AltoLeverageSwapperInvalidSwapTarget(params.swapTarget);
        }

        // pull tokens from AltoLeverage contract to this contract
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(sellToken).forceApprove(params.swapTarget, amountIn);

        uint256 sellTokenBalanceBefore = IERC20(sellToken).balanceOf(address(this)) - amountIn;
        uint256 buyTokenBalanceBefore = IERC20(buyToken).balanceOf(address(this));

        (bool success,) = params.swapTarget.call(params.swapData);
        if (!success) revert AltoLeverageSwapperSwapFailed();

        IERC20(sellToken).forceApprove(params.swapTarget, 0);

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

        emit Swap(params.swapTarget, sellToken, buyToken, amountIn, buyTokenBalanceReceived, sellTokenBalanceLeftover);

        return buyTokenBalanceReceived;
    }
}
