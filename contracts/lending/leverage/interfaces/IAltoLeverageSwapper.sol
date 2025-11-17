// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct SwapParams {
    /// @notice the minimum amount of buyToken to buy
    uint256 minAmountOut;
    /// @notice the swap calldata to pass to the swap target contract
    bytes swapData;
}

interface IAltoLeverageSwapperErrors {
    /// @notice error thrown when the sender is not whitelisted
    error AltoLeverageSwapperSenderNotValid(address sender);

    /// @notice error thrown when the input is invalid
    error AltoLeverageSwapperInvalidInput();

    /// @notice error thrown when the swap failed
    error AltoLeverageSwapperSwapFailed();

    /// @notice error thrown when the minimum expected buyToken balance received is not met
    error AltoLeverageSwapperMinAmountOutNotMet(uint256 minAmountOut, uint256 buyTokenBalanceReceived);
}

interface IAltoLeverageSwapperEvents {
    /// @notice event emitted when the whitelist is set
    /// @param contractAddress the address that was whitelisted
    /// @param isWhitelisted true if the contract is whitelisted, false otherwise
    event SetWhitelisted(address indexed contractAddress, bool isWhitelisted);

    /// @notice event emitted when the swap is executed
    /// @param sellToken the token that was sold
    /// @param buyToken the token that was bought
    /// @param amountIn the amount of sellToken that was approved for the swap
    /// @param amountOut the amount of buyToken that was bought
    /// @param amountLeftover the amount of sellToken that was leftover
    event Swap(
        address indexed sellToken, address indexed buyToken, uint256 amountIn, uint256 amountOut, uint256 amountLeftover
    );
}

interface IAltoLeverageSwapper is IAltoLeverageSwapperErrors, IAltoLeverageSwapperEvents {
    /// @notice returns if an address is whitelisted to call the swap function
    /// @param _address the address to check
    /// @return isWhitelisted true if the address is whitelisted, false otherwise
    function isWhitelisted(address _address) external view returns (bool);

    /// @notice sets if an address is whitelisted
    /// @param _address the address to set
    /// @param _isWhitelisted if the address is whitelisted
    function setWhitelisted(address _address, bool _isWhitelisted) external;

    //// @notice function that should swaps a token for another
    /// @param sellToken the token to sell
    /// @param buyToken the token to buy
    /// @param amountIn the amount of sellToken to sell
    /// @param swapParams ABI-encoded swap parameter (see `SwapParams` struct for details)
    /// @return amountOut the amount of buyToken bought
    /// @dev IMPORTANT:This function has to implement "minAmountOut" check using data proovided by `swapParams`
    function swap(address sellToken, address buyToken, uint256 amountIn, bytes calldata swapParams)
        external
        payable
        returns (uint256 amountOut);
}
