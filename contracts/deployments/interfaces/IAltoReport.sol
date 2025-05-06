// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct AltoReport {
    address bundler3;
    address altoAdapter;
    address borrowMarket;
    address borrowIrm;
    address borrowOracle;
    address mintMarket;
    address mintIrm;
    address mintOracle;
    address simpleLeverageExecutor;
    address zeroXSwapper;
    address multiTokenSender;
    address tapiocaMulticall;
    address usdo;
}

struct UtilitiesReport {
    address tapiocaMulticall;
    address pauser;
    address zeroXSwapper;
    address multiTokenSender;
    address bundler3;
    address altoAdapter;
    address borrowIrm;
    address mintIrm;
}

struct LendingReport {
    address borrowMarket;
    address borrowIrm;
    address borrowOracle;
    address mintMarket;
    address mintIrm;
    address mintOracle;
}

struct TapiocaInput {
    address owner;
    address wrappedNativeToken;
    address zeroXProxy;
    address tapToken;
    address lzEndpoint;
    uint256 bbMarketBorrowCap;
    uint16 lzChainId;
    bool isTestnet;
    bool isMetaInstance; // if false, it will deploy a host Tapioca instance (Arbitrum), if not, it will deploy a meta instance deployment (Other networks, like Ethereum)
    address collateralTokenBorrowMarket;
    address collateralTokenMintMarket;
    address borrowOracle;
    address mintOracle;
    address usdc;
    address stETH;
}

struct UsdoReport {
    address usdo;
    address usdoFlashloanHelper;
}

struct Reports {
    UtilitiesReport utilitiesReport;
    UsdoReport usdoReport;
    LendingReport lendingReport;
}
