// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

uint256 constant USD_ORACLE_PRICE_PRECISION = 1e8;

interface IUsdOracle {
    function getPrice() external view returns (uint256);
}
