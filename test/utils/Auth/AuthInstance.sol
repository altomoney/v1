// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auth} from "tap-utils/utils/Auth.sol";
import {ErrorsLib} from "tap-lending/libraries/ErrorsLib.sol";
import {DOMAIN_TYPEHASH} from "tap-utils/utils/Constants.sol";

contract AuthInstance is Auth {
    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(address => uint256) public values;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function setValue(address onBehalf, uint256 value) external {
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);
        values[onBehalf] = value;
    }

    function _getDomainSeparator() internal view override returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }
}
