// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {
    DusdPegOracleCurveRawPoolState,
    DusdPegOracleCurveRuntimeConfig,
    IDusdPegOracleCurve,
    IDusdPegOracleCurveBase
} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";

/// @notice Interface-faithful DUSD peg oracle double with a configurable price
/// observation and failure mode.
contract MockDusdPegOracle is IDusdPegOracleCurve {
    error MockDusdPegOracleGetPriceReverted();

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public constant override ORACLE_INDEX = 0;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public constant override EXPECTED_COIN_COUNT = 2;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint8 public constant override STANDARD_ASSET_TYPE = 0;

    /// @inheritdoc IDusdPegOracleCurveBase
    uint256 public constant override PRICE_TIMESTAMP_MASK = type(uint128).max;

    /// @inheritdoc IDusdPegOracleCurveBase
    address public override curvePool;

    /// @inheritdoc IDusdPegOracleCurveBase
    DusdPegOracleCurveRuntimeConfig public override runtimeConfig;

    uint256 private s_priceWad;
    uint48 private s_observedAt;
    bool private s_valid;
    bool private s_getPriceReverts;

    /// @notice Sets the exact observation returned by `getPrice`.
    function setPrice(uint256 priceWad_, uint48 observedAt_, bool valid_) external {
        s_priceWad = priceWad_;
        s_observedAt = observedAt_;
        s_valid = valid_;
    }

    /// @notice Enables or disables a revert from `getPrice`.
    function setGetPriceReverts(bool reverts_) external {
        s_getPriceReverts = reverts_;
    }

    /// @inheritdoc IDusdPegOracleCurveBase
    function getPrice() external view override returns (uint256 priceWad, uint48 observedAt, bool valid) {
        if (s_getPriceReverts) revert MockDusdPegOracleGetPriceReverted();
        return (s_priceWad, s_observedAt, s_valid);
    }

    /// @inheritdoc IDusdPegOracleCurveBase
    function setRuntimeConfig(DusdPegOracleCurveRuntimeConfig calldata newRuntimeConfig) external override {
        runtimeConfig = newRuntimeConfig;
        emit SetRuntimeConfig(newRuntimeConfig);
    }

    /// @inheritdoc IDusdPegOracleCurve
    function rawPoolState() external pure override returns (DusdPegOracleCurveRawPoolState memory state) {}
}
