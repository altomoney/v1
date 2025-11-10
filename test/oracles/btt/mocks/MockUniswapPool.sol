// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";

/// @notice Mock Uniswap V3 Pool for testing purposes
contract MockUniswapPool {
    address inToken;
    address outToken;

    constructor() {
        inToken = address(new ERC20Mock("In Token", "IN"));
        outToken = address(new ERC20Mock("Out Token", "OUT"));
    }

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

    function token0() external view returns (address) {
        return address(inToken);
    }

    function token1() external view returns (address) {
        return address(outToken);
    }
}
