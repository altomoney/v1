// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IBoldWrapperErrors {
    // @notice error thrown when the input is invalid
    error BoldWrapperInvalidInput();
}

interface IBoldWrapperEvents {
    // @notice event emitted when the BOLD token is wrapped
    event Wrap(uint256 amount, uint256 sBoldAmount);
    // @notice event emitted when the SBOLD token is unwrapped
    event Unwrap(uint256 amount, uint256 boldAmount);
}

interface IBoldWrapper is IBoldWrapperErrors, IBoldWrapperEvents {
    // @notice returns the SBOLD token address
    function SBOLD() external view returns (address);
    // @notice returns the BOLD token address
    function BOLD() external view returns (address);

    // @notice wraps the BOLD token to the SBOLD token
    // @param amount the amount of BOLD token to wrap
    // @param receiver the receiver of the SBOLD token
    function wrap(uint256 amount, address receiver) external;

    // @notice unwraps the SBOLD token to the BOLD token
    // @param amount the amount of SBOLD token to unwrap
    // @param receiver the receiver of the BOLD token
    function unwrap(uint256 amount, address receiver) external;
}
