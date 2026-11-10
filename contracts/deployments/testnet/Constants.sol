// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

uint128 constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;
address constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
uint256 constant ALTO_TOKEN_TOTAL_SUPPLY = 100_000_000 ether;
uint256 constant DUSD_TOKEN_SUPPLY_TO_CONTRACTS = 100_000_000_000 ether;

function getMulticallOwnerAddresses() pure returns (address[] memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = 0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367;
    addresses[1] = 0xFC3567948D827F928a82cF1263c5851a74BD90C9;
    return addresses;
}

function getMerkleManagerUpdaters() pure returns (address[] memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = 0x16C875e06071F85b683acAb4612744F9aAFc8c0B;
    addresses[1] = 0xe963e85F639C6aD44FAc75f401fB97C5ac9eb089;
    return addresses;
}
