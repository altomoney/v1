// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @notice Mock Uniswap V3 Pool for testing purposes
contract MockUniswapPool {
    function increaseObservationCardinalityNext(uint16) external {}

    function observe(uint32[] calldata)
        external
        pure
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](2);
        secondsPerLiquidityCumulativeX128s = new uint160[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = 1000;
        secondsPerLiquidityCumulativeX128s[0] = 0;
        secondsPerLiquidityCumulativeX128s[1] = 1000;
    }
}
