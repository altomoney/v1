// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IWrapper {
    // @notice returns the Base token which is not wrapped
    function BASE_TOKEN() external view returns (address);
    // @notice returns the Wrapped token
    function WRAPPED_TOKEN() external view returns (address);

    // @notice wraps the Base token to the Wrapped token
    // @param amount the amount of base token to wrap
    // @param receiver the receiver of the wrapped token
    function wrap(uint256 amount, address receiver) external;

    // @notice unwraps the Wrapped token to the Base token
    // @param amount the amount of wrapped token to unwrap
    // @param receiver the receiver of the base token
    function unwrap(uint256 amount, address receiver) external;
}
