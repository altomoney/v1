// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";

/// @title Uint128ConverterMock
/// @notice Mock contract for testing Uint128Converter library
contract Uint128ConverterMock {
    using Uint128Converter for uint256;

    /// @notice Exposes the toUint128 function for testing
    /// @param x The value to convert
    /// @return The converted uint128 value
    function toUint128(uint256 x) external pure returns (uint128) {
        return x.toUint128();
    }
}
