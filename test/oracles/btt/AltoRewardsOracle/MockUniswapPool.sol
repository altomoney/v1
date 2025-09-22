// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @notice Mock Uniswap V3 Pool for testing purposes
contract MockUniswapPool {
    function increaseObservationCardinalityNext(uint16) external {}

    function slot0()
        external
        pure
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (1, 1, 1, 1, 1, 1, true);
    }

    function observe(uint32[] calldata)
        external
        pure
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](1);
        secondsPerLiquidityCumulativeX128s = new uint160[](1);
        tickCumulatives[0] = 0;
        secondsPerLiquidityCumulativeX128s[0] = 0;
    }

    function token0() external pure returns (address) {
        return address(0x1);
    }

    function token1() external pure returns (address) {
        return address(0x2);
    }
}
