// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {UniswapUtils, IUniswapV3Pool} from "@alto/oracles/utils/UniswapUtils.sol";

/// @title ModuleUniswapMulti
/// @author Pearl Labs
/// @author Adapted from Angle Core (https://github.com/AngleProtocol/angle-core)
/// @notice Module Contract that is going to be used to help compute Uniswap prices
/// @dev This contract will help for an oracle using multiple UniswapV3 pools
/// @dev An oracle using Uniswap is either going to be a `ModuleUniswapSingle` or a `ModuleUniswapMulti`
abstract contract ModuleUniswapMulti is UniswapUtils {
    /// @notice Uniswap pools, the order of the pools to arrive to the final price should be respected
    IUniswapV3Pool[] public circuitUniswap;
    /// @notice Whether the rate obtained with each pool should be multiplied or divided to the current amount
    uint8[] public circuitUniIsMultiplied;

    error ModuleUniswapMultiInvalidInput();

    /// @notice Constructor for an oracle using multiple Uniswap pool
    /// @param _circuitUniswap Path of the Uniswap pools
    /// @param _circuitUniIsMultiplied Whether we should multiply or divide by this rate in the path
    /// @param _twapPeriod Time weighted average window, it is common for all Uniswap pools
    /// @param observationLength Number of observations that each pool should have stored
    constructor(
        IUniswapV3Pool[] memory _circuitUniswap,
        uint8[] memory _circuitUniIsMultiplied,
        uint32 _twapPeriod,
        uint16 observationLength
    ) {
        if (_twapPeriod == 0) {
            revert UniswapUtilsInvalidTwapPeriod();
        }

        uint256 circuitUniLength = _circuitUniswap.length;

        if (circuitUniLength == 0 || circuitUniLength != _circuitUniIsMultiplied.length) {
            revert ModuleUniswapMultiInvalidInput();
        }

        twapPeriod = _twapPeriod;
        emit UniswapUtilsTwapPeriodUpdated(twapPeriod, _twapPeriod);

        circuitUniswap = _circuitUniswap;
        circuitUniIsMultiplied = _circuitUniIsMultiplied;

        for (uint256 i = 0; i < circuitUniLength; i++) {
            circuitUniswap[i].increaseObservationCardinalityNext(observationLength);
        }
    }

    /// @notice Reads Uniswap current block oracle rate
    /// @param quoteAmount The amount in the in-currency base to convert using the Uniswap oracle
    /// @return The value of the oracle of the initial amount is then expressed in the decimal from
    /// the end currency
    function _quoteUniswap(uint256 quoteAmount) internal view returns (uint256) {
        for (uint256 i = 0; i < circuitUniswap.length; i++) {
            quoteAmount = _readUniswapPool(quoteAmount, circuitUniswap[i], circuitUniIsMultiplied[i]);
        }
        // The decimal here is the one from the end currency
        return quoteAmount;
    }
}
