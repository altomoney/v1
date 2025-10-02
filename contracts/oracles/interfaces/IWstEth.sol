// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IWstEth {
    /// @notice Returns the stETH per 1 token of wstETH
    function stEthPerToken() external view returns (uint256);
}
