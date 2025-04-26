// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";

contract OracleMock is IOracle {
    uint256 public override getPrice;

    function setPrice(uint256 newPrice) external {
        getPrice = newPrice;
    }
}
