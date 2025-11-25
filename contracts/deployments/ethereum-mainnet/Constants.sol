// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Tokens
// WETH on mainnet
address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
// wstETH on mainnet
address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
// rETH on mainnet
address constant RETH_MAINNET = 0xae78736Cd615f374D3085123A210448E74Fc6393;
// mETH on mainnet
address constant METH_MAINNET = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
// mETH staking contract on mainnet
address constant METH_STAKING_MAINNET = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
// tBTC (tBTC v2) on mainnet
address constant TBTC_MAINNET = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
// WBTC on mainnet
address constant WBTC_MAINNET = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
// cbBTC on mainnet
address constant CBBTC_MAINNET = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
// sUSDe on mainnet
address constant SUSDE_MAINNET = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
// USDC on mainnet
address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

// Chainlink feeds
// Standard Chainlink ETH/USD feed
address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
// Standard Chainlink BTC/USD feed
address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
// Standard Chainlink WBTC/BTC feed
address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
// Standard Chainlink USDe/USD feed
address constant CHAINLINK_USDE_USD_PRICE_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;

// Miscellaneous
// 0x.org swap target for Ethereum mainnet
address constant ZEROX_SWAP_TARGET_MAINNET = 0x0000000000001fF3684f28c67538d4D072C22734;
// Morpho's deployment of Bundler3
address constant BUNDLER3_MAINNET = 0x6566194141eefa99Af43Bb5Aa71460Ca2Dc90245;
// LayerZero endpoint for Ethereum mainnet
address constant LAYERZERO_ENDPOINT_MAINNET = 0x1a44076050125825900e736c501f859c50fE728c;

function getMulticallOwnerAddresses() pure returns (address[] memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = 0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367;
    addresses[1] = 0xFC3567948D827F928a82cF1263c5851a74BD90C9;
    return addresses;
}

