// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IAltoLeverageSwapperMultiTarget,
    IAltoLeverageSwapperMultiTargetErrors,
    IAltoLeverageSwapperMultiTargetEvents
} from "../leverage/interfaces/IAltoLeverageSwapper.sol";

struct SwapParamsWrapperToken {
    /// @notice the minimum amount of buyToken to buy
    uint256 minAmountOut;
    /// @notice the underlying PT token of the wrapper token
    address underlyingToken;
    /// @notice the selected swap target contract address
    address swapTarget;
    /// @notice the swap calldata to pass to the swap target contract
    bytes swapData;
}

interface IAltoLeverageSwapperForWrapperTokenErrors is IAltoLeverageSwapperMultiTargetErrors {
    /// @notice error thrown when the market is invalid
    error AltoLeverageSwapperForWrapperTokenInvalidMarket(address market);
}

interface IAltoLeverageSwapperForWrapperTokenEvents is IAltoLeverageSwapperMultiTargetEvents {}

interface IAltoLeverageSwapperForWrapperToken is
    IAltoLeverageSwapperMultiTarget,
    IAltoLeverageSwapperForWrapperTokenErrors,
    IAltoLeverageSwapperForWrapperTokenEvents
{
    /// @notice Returns the market address.
    function MARKET() external view returns (address);
}
