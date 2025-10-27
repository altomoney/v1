// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAltoLeverageSwapper, SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWrapper} from "@alto/lending/leverage/interfaces/IWrapper.sol";

/// @title AltoSboldLeverageSwapper
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice This contract is used to swap SBOLD tokens in AltoLeverage contract during levarage and deleverage
contract AltoSboldLeverageSwapper is IAltoLeverageSwapper, Ownable {
    using SafeERC20 for IERC20;

    /// @notice 0x Allowance holder contract
    address public immutable SWAP_TARGET;

    /// @notice the address of the SBOLD token
    address public immutable SBOLD;
    /// @notice the address of the BOLD token
    address public immutable BOLD;

    /// @inheritdoc IAltoLeverageSwapper
    mapping(address => bool) public isWhitelisted;

    /// @notice the bold wrapper contract to wrap and unwrap BOLD and SBOLD
    IWrapper public boldWrapper;

    event SetBoldWrapper(address indexed addr, address indexed boldWrapper);

    /// @notice constructor
    /// @param _owner the owner of the contract
    /// @param _swapTarget the address of the SWAP_TARGET
    constructor(address _owner, address _swapTarget, address _boldWrapper) Ownable(_owner) {
        if (_swapTarget == address(0) || _boldWrapper == address(0)) revert AltoLeverageSwapperInvalidInput();
        SWAP_TARGET = _swapTarget;

        emit SetBoldWrapper(address(0), address(_boldWrapper));
        boldWrapper = IWrapper(_boldWrapper);

        SBOLD = boldWrapper.WRAPPED_TOKEN();
        BOLD = boldWrapper.BASE_TOKEN();
    }

    /// @inheritdoc IAltoLeverageSwapper
    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        if (isWhitelisted[_address] == _isWhitelisted) revert AltoLeverageSwapperInvalidInput();

        isWhitelisted[_address] = _isWhitelisted;
        emit SetWhitelisted(_address, _isWhitelisted);
    }

    /// @notice sets the bold wrapper contract
    /// @param _boldWrapper the bold wrapper contract
    function setBoldWrapper(IWrapper _boldWrapper) external onlyOwner {
        if (address(_boldWrapper) == address(0)) revert AltoLeverageSwapperInvalidInput();

        emit SetBoldWrapper(address(boldWrapper), address(_boldWrapper));
        boldWrapper = _boldWrapper;
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

        // either sellToken or buyToken must be SBOLD
        if (buyToken != SBOLD && sellToken != SBOLD) {
            revert AltoLeverageSwapperInvalidInput();
        }

        // swap params would correspond to BOLD and not SBOLD
        SwapParams memory params = abi.decode(swapParams, (SwapParams));

        // pull tokens from AltoLeverage contract to this contract
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 sellTokenBalanceBefore = IERC20(sellToken).balanceOf(address(this)) - amountIn;
        uint256 buyTokenBalanceBefore = IERC20(buyToken).balanceOf(address(this));

        if (sellToken == SBOLD) {
            // sellToken is SBOLD
            // swap target would have route from BOLD to buyToken.
            // so SBOLD received needs to be unwrapped to BOLD

            // need to unwrap SBOLD to BOLD so that it can be used to swap
            IERC20(SBOLD).forceApprove(address(boldWrapper), amountIn);

            uint256 boldBalanceBefore = IERC20(BOLD).balanceOf(address(this));
            // unwraps SBOLD to BOLD
            boldWrapper.unwrap(amountIn, address(this));
            IERC20(SBOLD).forceApprove(address(boldWrapper), 0);
            uint256 boldBalanceReceived = IERC20(BOLD).balanceOf(address(this)) - boldBalanceBefore;

            // swapping BOLD received to buyToken
            IERC20(BOLD).forceApprove(SWAP_TARGET, boldBalanceReceived);
            (bool success,) = SWAP_TARGET.call(params.swapData);
            if (!success) revert AltoLeverageSwapperSwapFailed();
            IERC20(BOLD).forceApprove(SWAP_TARGET, 0);

            uint256 remainingBoldBalance = IERC20(BOLD).balanceOf(address(this)) - boldBalanceBefore;

            if (remainingBoldBalance > 0) {
                // wrapping BOLD balance not used for swapping to SBOLD again
                IERC20(BOLD).forceApprove(address(boldWrapper), remainingBoldBalance);
                boldWrapper.wrap(remainingBoldBalance, address(this));
                IERC20(BOLD).forceApprove(address(boldWrapper), 0);
            }
        } else {
            // buyToken is SBOLD
            // swap target would have route from sellToken -> BOLD.
            // BOLD received needs to be wrapped to SBOLD
            IERC20(sellToken).forceApprove(SWAP_TARGET, amountIn);

            uint256 boldBalanceBefore = IERC20(BOLD).balanceOf(address(this));
            (bool success,) = SWAP_TARGET.call(params.swapData);
            if (!success) revert AltoLeverageSwapperSwapFailed();
            uint256 boldBalanceReceived = IERC20(BOLD).balanceOf(address(this)) - boldBalanceBefore;
            IERC20(sellToken).forceApprove(SWAP_TARGET, 0);

            if (boldBalanceReceived > 0) {
                // wraps the BOLD received to SBOLD
                IERC20(BOLD).forceApprove(address(boldWrapper), boldBalanceReceived);
                boldWrapper.wrap(boldBalanceReceived, address(this));
                IERC20(BOLD).forceApprove(address(boldWrapper), 0);
            }
        }

        uint256 buyTokenBalanceReceived = IERC20(buyToken).balanceOf(address(this)) - buyTokenBalanceBefore;
        uint256 sellTokenBalanceLeftover = IERC20(sellToken).balanceOf(address(this)) - sellTokenBalanceBefore;

        // check that token to buy is received more than the minimum expected amount
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
