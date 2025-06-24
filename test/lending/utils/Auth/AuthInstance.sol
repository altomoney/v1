// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auth} from "@alto/utils/Auth.sol";

contract AuthInstance is Auth {
    mapping(address => uint256) public values;

    error Unauthorized();

    constructor() {}

    function setValue(address onBehalf, uint256 value) external {
        if (!_isSenderAuthorized(onBehalf)) {
            revert Unauthorized();
        }
        values[onBehalf] = value;
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
