// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

uint256 constant ORACLE_PRICE_PRECISION = 1e36;

interface IOracle {
    function getPrice() external view returns (uint256);

    function decimals() external view returns (uint8);
}
