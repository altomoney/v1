// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ITapToken {
    error TwTapAlreadySet();

    struct TapTokenConstructorData {
        uint256 epochDuration;
        address endpoint;
        address contributors;
        address earlySupporters;
        address supporters;
        address lTap;
        address dao;
        address airdrop;
        address owner;
    }
}
