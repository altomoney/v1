// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {
    IAltoLeverageSwapperMultiTarget,
    SwapParamsMultiTarget,
    IAltoLeverageSwapper
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAltoLeverageSwapperForWrapperToken, SwapParamsWrapperToken} from "./IAltoLeverageSwapperForWrapperToken.sol";
import {IWrapperToken} from "./IWrapperToken.sol";
import {IMarket} from "../interfaces/IMarket.sol";

/// @title AltoLeverageSwapperForWrapperToken
/// @custom:contact security@altofoundation.org
/// @notice This contract is used to swap tokens in AltoLeverage contract during levarage and deleverage
/// @dev This contract uses whitelisted swap targets instead of a single fixed swap target
/// @dev This Swapper should only be used for AltoLeverage contracts with wrapper tokens as collateral
/// @dev This contract unwraps collateral token to underlying token during sell of collateral token and
/// wraps underlying token back to collateral token during buy of collateral token.
/// @dev Contracts using this swapper must handle any reentrancy protection around `swap()` themselves
contract AltoLeverageSwapperForWrapperToken is IAltoLeverageSwapperForWrapperToken, Ownable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IAltoLeverageSwapperMultiTarget
    mapping(address => bool) public isValidSwapTarget;

    /// @inheritdoc IAltoLeverageSwapper
    mapping(address => bool) public isWhitelisted;

    address public immutable MARKET;

    /// @notice constructor
    /// @param _owner the owner of the contract
    /// @param _market the market address
    /// @param validSwapTargets the valid swap targets
    constructor(address _owner, address _market, address[] memory validSwapTargets) Ownable(_owner) {
        if (_market == address(0)) revert AltoLeverageSwapperInvalidInput();
        MARKET = _market;

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

    /// @inheritdoc IAltoLeverageSwapperMultiTarget
    function setValidSwapTarget(address _swapTarget, bool _isValid) external onlyOwner {
        if (_swapTarget == address(0)) revert AltoLeverageSwapperInvalidInput();
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

        address collateralTokenOfMarket = IMarket(MARKET).collateralToken();

        // one of the sellToken or buyToken must be the collateral token of the market
        if (sellToken != collateralTokenOfMarket && buyToken != collateralTokenOfMarket) {
            revert AltoLeverageSwapperInvalidInput();
        }

        SwapParamsWrapperToken memory params = abi.decode(swapParams, (SwapParamsWrapperToken));

        if (!isValidSwapTarget[params.swapTarget]) {
            revert AltoLeverageSwapperInvalidSwapTarget(params.swapTarget);
        }

        if (params.underlyingToken != IWrapperToken(collateralTokenOfMarket).underlyingToken()) {
            revert AltoLeverageSwapperInvalidInput();
        }

        // pull tokens to sell from AltoLeverage contract to this contract
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);

        // if the sellToken is the collateral token of the market
        if (sellToken == collateralTokenOfMarket) {
            // @dev swapRoute needs to be generated for the amountIn of underlying token if sellToken is collateral token of market
            amountIn = IWrapperToken(collateralTokenOfMarket).unwrap(amountIn);
            sellToken = params.underlyingToken;
        } else {
            // buyToken is collateralToken of market
            // @dev minAmountOut should correspond to underlying token amount if buyToken is collateral token of market
            buyToken = params.underlyingToken;
        }

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
            _refundLeftover(sellToken, collateralTokenOfMarket, sellTokenBalanceLeftover);
        }

        uint256 returnAmount = buyTokenBalanceReceived;
        if (buyTokenBalanceReceived > 0) {
            address tokenToTransfer = buyToken;
            if (buyToken == params.underlyingToken) {
                IERC20(params.underlyingToken).forceApprove(collateralTokenOfMarket, buyTokenBalanceReceived);
                returnAmount = IWrapperToken(collateralTokenOfMarket).wrap(buyTokenBalanceReceived);
                IERC20(params.underlyingToken).forceApprove(collateralTokenOfMarket, 0);
                tokenToTransfer = collateralTokenOfMarket;
            }
            IERC20(tokenToTransfer).safeTransfer(msg.sender, returnAmount);
        }

        emit Swap(params.swapTarget, sellToken, buyToken, amountIn, buyTokenBalanceReceived, sellTokenBalanceLeftover);

        return returnAmount;
    }

    /// @dev Rewraps unspent underlying, left when collateral was unwrapped and sold, so the sender gets back the
    /// collateral token it sold.
    function _refundLeftover(address sellToken, address collateralToken, uint256 leftover) private {
        if (
            sellToken == IWrapperToken(collateralToken).underlyingToken()
                && IWrapperToken(collateralToken).previewWrap(leftover) > 0
        ) {
            IERC20(sellToken).forceApprove(collateralToken, leftover);
            uint256 wrappedLeftover = IWrapperToken(collateralToken).wrap(leftover);
            IERC20(sellToken).forceApprove(collateralToken, 0);
            IERC20(collateralToken).safeTransfer(msg.sender, wrappedLeftover);
        } else {
            IERC20(sellToken).safeTransfer(msg.sender, leftover);
        }
    }
}
