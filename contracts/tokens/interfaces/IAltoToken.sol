// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface IAltoToken {
    error AltoTokenNotAuthorized();

    event SetMinterStatus(address indexed _for, bool _status);
    event SetBurnerStatus(address indexed _for, bool _status);
}
