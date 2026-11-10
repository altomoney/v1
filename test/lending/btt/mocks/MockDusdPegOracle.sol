// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {IDusdPegOracle} from "@alto/oracles/interfaces/IDusdPegOracle.sol";

/// @notice Interface-faithful DUSD peg oracle double with a configurable price
/// observation and failure mode.
contract MockDusdPegOracle is IDusdPegOracle {
    error MockDusdPegOracleGetPriceReverted();

    uint256 private s_priceWad;
    uint48 private s_observedAt;
    bool private s_valid;
    bool private s_getPriceReverts;

    /// @notice Sets the exact observation returned by `getPrice`.
    function setPrice(uint256 priceWad, uint48 observedAt, bool valid) external {
        s_priceWad = priceWad;
        s_observedAt = observedAt;
        s_valid = valid;
    }

    /// @notice Enables or disables a revert from `getPrice`.
    function setGetPriceReverts(bool reverts) external {
        s_getPriceReverts = reverts;
    }

    /// @inheritdoc IDusdPegOracle
    function getPrice() external view override returns (uint256 priceWad, uint48 observedAt, bool valid) {
        if (s_getPriceReverts) revert MockDusdPegOracleGetPriceReverted();
        return (s_priceWad, s_observedAt, s_valid);
    }
}
