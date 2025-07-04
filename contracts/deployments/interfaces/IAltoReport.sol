// SPDX-License-Identifier: MIT
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
    address altoLeverage;
    address leverageSwapper;
    address multiTokenSender;
    address altoMulticall;
    address usdo;
    address altoToken;
    address rewardsDistributor;
    address twAltoStaking;
}

struct UtilitiesReport {
    address altoMulticall;
    address leverageSwapper;
    address multiTokenSender;
    address bundler3;
    address altoAdapter;
    address borrowIrm;
    address altoLeverage;
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

struct AltoInput {
    address owner;
    address wrappedNativeToken;
    address altoToken;
    address lzEndpoint;
    uint256 bbMarketBorrowCap;
    uint16 lzChainId;
    bool isTestnet;
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

struct AltoTokenReport {
    address rewardsDistributor;
    address twAltoStaking;
}

struct Reports {
    UtilitiesReport utilitiesReport;
    UsdoReport usdoReport;
    LendingReport lendingReport;
    AltoTokenReport altoTokenReport;
}
