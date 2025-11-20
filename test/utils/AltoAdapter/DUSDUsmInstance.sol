// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";

contract DUSDUsmInstance is DUSDUsm {
    constructor(address dusd, address underlyingAsset) DUSDUsm(dusd, underlyingAsset) {}

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}

