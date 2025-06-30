// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {IOracle as IChainlinkOracle} from "@alto/rewards/interfaces/IRewardsDistributor.sol";

contract OracleUsdMock is IOracle, IChainlinkOracle {
    int256 private price;

    function setPrice(uint256 newPrice) external {
        price = int256(newPrice);
    }

    function latestAnswer() external view returns (int256) {
        return price;
    }

    function decimals() external view override(IOracle, IChainlinkOracle) returns (uint8) {
        return 8;
    }

    function getPrice() external view override returns (uint256) {
        return uint256(price);
    }
}
