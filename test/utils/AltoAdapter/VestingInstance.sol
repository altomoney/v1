// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoVesting} from "@alto/vesting/AltoVesting.sol";

contract VestingInstance is AltoVesting {
    constructor(
        address _owner,
        uint256 _initialTimelock,
        bool _isVestingUpdatable,
        address _vestingToken,
        bytes32 _merkleRoot,
        bytes32 _ipfsHash
    ) AltoVesting(_owner, _initialTimelock, _isVestingUpdatable, _vestingToken, _merkleRoot, _ipfsHash) {}

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
