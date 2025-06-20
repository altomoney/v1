// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";

contract OracleUsdMock is IOracle {
    uint256 public override getPrice;

    function setPrice(uint256 newPrice) external {
        getPrice = newPrice;
    }
}
