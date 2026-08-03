// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IDusdPegOracle {
    /// @notice Returns the current DUSD/USD price and associated metadata.
    ///
    /// @return priceWad    DUSD/USD price using 1e18 precision.
    /// @return observedAt  Timestamp represented by the observation.
    /// @return valid       Whether the observation passed the oracle's checks.
    function getPrice() external view returns (uint256 priceWad, uint48 observedAt, bool valid);
}
