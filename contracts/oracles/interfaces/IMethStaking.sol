// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IMethStaking {
    function mETHToETH(uint256 _mETHAmount) external view returns (uint256);
}
