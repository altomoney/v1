// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IMintableERC20
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for mintable ERC20 tokens.
/// @dev This is used as a borrow token in the AltoMintMarket contract.
interface IMintableERC20 is IERC20 {
    /// @notice Mints tokens to an address.
    /// @param to The address to mint tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external;

    /// @notice Burns tokens from an address.
    /// @param from The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    function burn(address from, uint256 amount) external;
}
