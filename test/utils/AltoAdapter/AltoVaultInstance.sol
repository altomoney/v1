// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoVault} from "@alto/lending/vault/AltoVault.sol";

contract AltoVaultInstance is AltoVault {
    constructor(address owner, uint256 initialTimelock, address _asset, string memory _name, string memory _symbol)
        AltoVault(owner, initialTimelock, _asset, _name, _symbol)
    {}
}
