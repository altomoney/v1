// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";

contract RewardsDistributorInstance is AltoRewardsDistributor {
    constructor(address _owner, uint256 _merkleRootTimelock, address _rewardTokenAddress)
        AltoRewardsDistributor(_owner, _merkleRootTimelock, _rewardTokenAddress)
    {}

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
