pragma solidity ^0.8.0;

interface ISharePriceCalculator {
    /// @notice Returns the USD value of 1e18 reUSD
    /// @return USD value of 1e18 reUSD
    function getSharePrice() external view returns (uint256);
}
