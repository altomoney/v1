// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniversalRewardsDistributor} from "@alto/utils/UniversalRewardsDistributor.sol";

contract UniversalRewardsDistributorInstance is UniversalRewardsDistributor {
    constructor(address _owner, uint256 _initialTimelock) UniversalRewardsDistributor(_owner, _initialTimelock) {}

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
