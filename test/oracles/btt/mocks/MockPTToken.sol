// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract MockPTToken {
    uint256 private _expiry;

    constructor(uint256 expiry_) {
        _expiry = expiry_;
    }

    function expiry() external view returns (uint256) {
        return _expiry;
    }
}
