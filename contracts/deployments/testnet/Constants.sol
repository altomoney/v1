// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

uint128 constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;
address constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
uint256 constant ALTO_TOKEN_TOTAL_SUPPLY = 100_000_000 ether;
uint256 constant DUSD_TOKEN_SUPPLY_TO_CONTRACTS = 100_000_000_000 ether;

function getMulticallOwnerAddresses() pure returns (address[] memory) {
    address[] memory addresses = new address[](1);
    addresses[0] = 0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367;
    return addresses;
}
