// SPDX-License-Identifier: GPL-3.0-or-later
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
// SyrupUSDC on mainnet
address constant SYRUPUSDC_MAINNET = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
// PAXG on mainnet
address constant PAXG_MAINNET = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
// frxUsd on mainnet
address constant FRXUSD_MAINNET = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
// frxUsd/dUSD Curve pool on mainnet
address constant FRXUSD_DUSD_CURVE_POOL_MAINNET = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
// Curve StableSwap NG factory that registered the frxUSD/DUSD pool on mainnet
address constant CURVE_STABLESWAP_NG_FACTORY_MAINNET = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
// Curve StableSwap NG implementation used by the registered frxUSD/DUSD pool on mainnet
address constant FRXUSD_DUSD_CURVE_POOL_IMPLEMENTATION_MAINNET = 0xDCc91f930b42619377C200BA05b7513f2958b202;
// poolId of frxUsd/dUSD Curve pool on mainnet
uint256 constant POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET = 565;
// Convex reward pool with staking token of curve LP token of frxUsd/dUSD poolon mainnet
address constant CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET = 0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb;
// Convex booster contract on mainnet
address constant CONVEX_BOOSTER_MAINNET = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
// Curve DAO(CRV) token address on mainnet
address constant CRV_TOKEN_MAINNET = 0xD533a949740bb3306d119CC777fa900bA034cd52;
// Convex token address on mainnet
address constant CVX_TOKEN_MAINNET = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
// Wrapped Frax token address on mainnet
address constant WFRAX_TOKEN_MAINNET = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;
// REUSD Share Price Calculator on mainnet
address constant REUSD_SHARE_PRICE_CALCULATOR_MAINNET = 0xd1D104a7515989ac82F1AFDa15a23650411b05B8;
// PT-reUSD on mainnet
address constant PT_REUSD_MAINNET = 0x3EAA0F0f0A5d3D595ae4e4b0D27f439d01c3E7b2;

// sDUSD/frxUSD Curve pool and LP token on mainnet
address constant SDUSD_FRXUSD_CURVE_POOL_MAINNET = 0x6cfD300bF4e3F879ba0C33c800eaA0B54f310578;
// sDUSD/frxUSD Curve gauge on mainnet
address constant SDUSD_FRXUSD_CURVE_GAUGE_MAINNET = 0xF56E9E4351Ee8c67176e37aaF7Bc4dA174f8A633;
// Convex pool ID for the sDUSD/frxUSD Curve LP token on mainnet
uint256 constant POOL_ID_SDUSD_FRXUSD_CURVE_POOL_MAINNET = 593;
// Convex reward pool for staked sDUSD/frxUSD Curve LP tokens on mainnet
address constant CONVEX_REWARD_POOL_CVX_SDUSD_FRXUSD_MAINNET = 0x97F029a72A5498d5A0F2d12D3FA89a134199706F;
// Stake DAO sDUSD/frxUSD reward vault on mainnet
address constant STAKEDAO_REWARD_VAULT_SDUSD_FRXUSD_MAINNET = 0xEe4A4cd4eBcb57EBbC7e4DF451F090896c6F88DF;
// Yearn v2 sDUSD/frxUSD vault on mainnet
address constant YEARN_VAULT_SDUSD_FRXUSD_MAINNET = 0x1dCDdAaC98e3b9D3466fc808B7787FA4CfAF9813;

// Chainlink feeds
// Standard Chainlink ETH/USD feed
address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
// Standard Chainlink BTC/USD feed
address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
// Standard Chainlink WBTC/BTC feed
address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
// Standard Chainlink USDe/USD feed
address constant CHAINLINK_USDE_USD_PRICE_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
// Standard Chainlink USDC/USD feed
address constant CHAINLINK_USDC_USD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
// Standard Chainlink PAXG/USD feed
address constant CHAINLINK_PAXG_USD_PRICE_FEED = 0x9944D86CEB9160aF5C5feB251FD671923323f8C3;
// ReProtocolExchangeRateChainlinkAdapter feed by Re-protocol
address constant CHAINLINK_REUSD_USD_PRICE_FEED = 0x72B5760cFBE437DD01409f44055fDfB8f8121B46;
// Standard Chainlink FRXUSD/USD feed
address constant CHAINLINK_FRXUSD_USD_PRICE_FEED = 0x9B4a96210bc8D9D55b1908B465D8B0de68B7fF83;

// Miscellaneous
// 0x.org swap target for Ethereum mainnet
address constant ZEROX_SWAP_TARGET_MAINNET = 0x0000000000001fF3684f28c67538d4D072C22734;
// OneInch Aggregation Router V6 on Ethereum mainnet
address constant ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET = 0x111111125421cA6dc452d289314280a0f8842A65;
// KyberSwap Meta Aggregation Router V2 on Ethereum mainnet
address constant KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
// Velora's Augustus Swapper on Ethereum mainnet
address constant VELORA_AUGUSTUS_MAINNET = 0x6A000F20005980200259B80c5102003040001068;
// Nordstern Router on Ethereum mainnet
address constant NORDSTERN_ROUTER_MAINNET = 0xa929c559E5e6537359680F39CB4E3708E1a14dd1;
// Morpho's deployment of Bundler3
address constant BUNDLER3_MAINNET = 0xAc80387009231b4D55B85Df27924B85f2ED6823D;
// LayerZero endpoint for Ethereum mainnet
address constant LAYERZERO_ENDPOINT_MAINNET = 0x1a44076050125825900e736c501f859c50fE728c;

// Deployed implementation contracts (shared across all markets of same type)
address constant ALTO_MINT_MARKET_IMPL = 0xFa82D4a97C2E7Ac747A37d1c3e2a4782dee8DE67;
address constant ALTO_BORROW_MARKET_IMPL = 0x29B6e2D9BfFCb4d70AC568CD0Ff93F61e79c9b57;

function getMulticallOwnerAddresses() pure returns (address[] memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = 0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367;
    addresses[1] = 0xFC3567948D827F928a82cF1263c5851a74BD90C9;
    return addresses;
}

/// @dev keccak256 of the runtime code deployed at the mainnet IRM factories, recorded at deployment time and verified on
/// Etherscan. The factories embed the IRM creation code including its compiler metadata, so a fresh compile only matches
/// while every source file is byte-identical.
bytes32 constant OWNER_PEG_RESPONSIVE_IRM_FACTORY_CODEHASH_MAINNET =
    0x5014f78c563691af81779822cf6b0fc663ca18a4666377a6c8a035ae84f4d11f;
bytes32 constant OWNER_FIXED_RATE_IRM_FACTORY_CODEHASH_MAINNET =
    0x464337bbcb57333a9a5b6dc5de919e414f4228eafa8d3f54909ae0a19ed41d59;
