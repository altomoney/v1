// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

struct TapiocaReport {
    address magnetar;
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
    address magnetarAssetModule;
    address magnetarYieldboxModule;
    address magnetarHelper;
    address zeroXSwapper;
    address toeHelper;
    address cluster;
    address pearlmit;
    address adbTapOptionOracle;
    address yieldbox;
    address yieldboxUri;
    address tapiocaMulticall;
}

struct MagnetarReport {
    address magnetar;
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
    address magnetarYieldboxModule;
    address magnetarMintXChainModule;
    address magnetarAssetXChainModule;
    address magnetarBaseModuleExternal;
    address magnetarHelper;
}

struct MagnetarDepsReport {
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
    address magnetarYieldboxModule;
}

struct UtilitiesReport {
    address tapiocaMulticall;
    address pearlmit;
    address cluster;
    address toeHelper;
    address pauser;
    address zeroXSwapper;
}

struct TapiocaInput {
    address owner;
    address wrappedNativeToken;
    address zeroXSwapper;
    address tapToken;
    uint16 lzChainId;
    bool isTestnet;
}

struct YieldboxReport {
    address yieldbox;
    address yieldboxUri;
    address delegate;
}

struct UsdoModulesReport {
    address usdoSenderModule;
    address usdoReceiverModule;
}

struct UsdoMarketModulesReport {
    address marketReceiverModule;
    address optionReceiverModule;
}

struct UsdoReport {
    address usdo;
}
