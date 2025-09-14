// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract OracleTestnet is IOracle, Ownable {
    uint256 public getPrice;

    constructor(address owner) Ownable(owner) {}

    function setPrice(uint256 newPrice) external onlyOwner {
        getPrice = newPrice;
    }
}
