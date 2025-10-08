pragma solidity ^0.8.22;

interface IReth {
    function getExchangeRate() external view returns (uint256);
}
