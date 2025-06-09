// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../../contracts/oracles/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    uint256 private _price;

    function setPrice(uint256 price) external {
        _price = price;
    }

    function getPrice() external view override returns (uint256) {
        return _price;
    }
}
