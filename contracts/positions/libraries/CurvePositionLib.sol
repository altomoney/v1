// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICurveStablePool} from "../interfaces/ICurveStablePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CurvePositionLib
/// @notice Internal helpers for Curve stable pool liquidity operations(addLiquidity and removeLiquidity)
/// @dev This library only supports curve pool which has 2 underlying tokens(i.e. N_COINS of pool is 2)
library CurvePositionLib {
    using SafeERC20 for IERC20;

    /// @notice Adds two pool coins as liquidity and mints LP to `position`.
    /// @dev The token0 and token1 sequence passed can be different from the pool's underlying tokens sequence
    /// @param position The address of the position to mint LP to
    /// @param curvePool The address of the curve pool to add liquidity to
    /// @param token0 The address of the first underlying token
    /// @param token1 The address of the second underlying token
    /// @param token0Amount The amount of the first underlying token to add
    /// @param token1Amount The amount of the second underlying token to add
    /// @param minLpOut The minimum amount of LP tokens to mint
    /// @return lpMinted The amount of LP tokens minted
    function addLiquidity(
        address position,
        address curvePool,
        address token0,
        address token1,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 minLpOut
    ) internal returns (uint256 lpMinted) {
        if (token0Amount == 0 && token1Amount == 0) return 0;

        IERC20(token0).forceApprove(curvePool, token0Amount);
        IERC20(token1).forceApprove(curvePool, token1Amount);

        // array of amounts to pass to curve pool according to sequence of tokens in curve pool
        uint256[] memory amounts = _amountsForPool(curvePool, token0, token1, token0Amount, token1Amount);
        // mint LP tokens from curve pool
        lpMinted = ICurveStablePool(curvePool).add_liquidity(amounts, minLpOut, position);

        IERC20(token0).forceApprove(curvePool, 0);
        IERC20(token1).forceApprove(curvePool, 0);
    }

    /// @notice Removes Curve liquidity back to the caller.
    /// @dev The token0 and token1 sequence passed can be different from the pool's underlying tokens sequence
    /// @param curvePool The address of the curve pool to remove liquidity from
    /// @param token0 The address of the first underlying token
    /// @param token1 The address of the second underlying token
    /// @param lpAmount The amount of LP tokens to remove
    /// @param minToken0Out The minimum amount of token0 to remove
    /// @param minToken1Out The minimum amount of token1 to remove
    function removeLiquidity(
        address curvePool,
        address token0,
        address token1,
        uint256 lpAmount,
        uint256 minToken0Out,
        uint256 minToken1Out
    ) internal {
        if (lpAmount == 0) return;

        // array of minimum amounts to pass to curve pool according to sequence of tokens in curve pool
        uint256[] memory minAmounts = _amountsForPool(curvePool, token0, token1, minToken0Out, minToken1Out);

        // burns the LP tokens and returns the amounts of underlying tokens to the caller
        ICurveStablePool(curvePool).remove_liquidity(lpAmount, minAmounts);
    }

    /// @notice Returns the amounts of underlying tokens to add or remove from the curve pool according to the sequence of tokens in curve pool
    /// @param curvePool The address of the curve pool to add or remove liquidity from
    /// @param token0 The address of the token0
    /// @param token1 The address of the token1
    /// @param token0Amount The amount of the token0 to add or remove
    /// @param token1Amount The amount of the token1 to add or remove
    /// @return amounts The amounts of token0 and token1 to add or remove from the curve pool according to sequence of tokens in curve pool
    function _amountsForPool(
        address curvePool,
        address token0,
        address token1,
        uint256 token0Amount,
        uint256 token1Amount
    ) private view returns (uint256[] memory amounts) {
        // this only supports curve pool with 2 underlying tokens
        amounts = new uint256[](2);
        amounts[0] = ICurveStablePool(curvePool).coins(0) == token0 ? token0Amount : token1Amount;
        amounts[1] = ICurveStablePool(curvePool).coins(1) == token0 ? token0Amount : token1Amount;
    }
}
