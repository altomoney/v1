// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct TapiocaReport {
    address magnetar;
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
    address magnetarAssetModule;
    address magnetarHelper;
    address simpleLeverageExecutor;
    address toftHelper;
    address zeroXSwapper;
    address toeHelper;
    address cluster;
    address pearlmit;
    address adbTapOptionOracle;
    address tapiocaMulticall;
    address extExec;
    address liquidatorReceiver;
    address usdoSenderModule;
    address usdoReceiverModule;
    address marketReceiverModule;
    address optionReceiverModule;
    address usdo;
    address sglInit;
    address sglInterestHelper;
    address sglLiquidationModule;
    address sglBorrowModule;
    address sglCollateralModule;
    address sglLeverageModule;
    address singularity;
    address penrose;
    address tapStrat;
    address wrappedTokenStrat;
    address usdoStrat;
    address marketHelper;
    address bbLiquidation;
    address bbBorrow;
    address bbCollateral;
    address bbLeverage;
    address bbDebtRateHelper;
    address bigbang;
    address tOFTSenderModule;
    address tOFTReceiverModule;
    address tOFTMarketReceiverModule;
    address tOFTOptionsReceiverModule;
    address tOFTGenericReceiverModule;
    address mTOFTReceiverModule;
}

struct MagnetarReport {
    address magnetar;
    address magnetarHelper;
    address simpleLeverageExecutor;
}

struct MagnetarDepsReport {
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
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
    address lzEndpoint;
    uint16 lzChainId;
    bool isTestnet;
    bool isMetaInstance; // if false, it will deploy a host Tapioca instance (Arbitrum), if not, it will deploy a meta instance deployment (Other networks, like Ethereum)
}

struct YieldboxReport {
    address yieldbox;
    address yieldboxUri;
    address extExec;
    address liquidatorReceiver;
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
    address usdoHelper;
    address usdoFlashloanHelper;
}

struct SGLReport {
    address sglInit;
    address sglInterestHelper;
    address sglLiquidationModule;
    address sglBorrowModule;
    address sglCollateralModule;
    address sglLeverageModule;
    address singularity;
}

struct PenroseReport {
    address penrose;
    address tapStrat;
    address wrappedTokenStrat;
    address usdoStrat;
    address marketHelper;
}

struct BBReport {
    address bbLiquidation;
    address bbBorrow;
    address bbCollateral;
    address bbLeverage;
    address bbDebtRateHelper;
    address bigbang;
}

struct IPenroseInput {
    address yieldbox;
    address cluster;
    address tapToken;
    address usdoToken;
    address nativeWrappedToken;
    address pearlmit;
    address owner;
    address singularityMaster;
    address bigbangMaster;
    address prevPenrose;
}

struct TOFTModulesReport {
    address tOFTSenderModule;
    address tOFTReceiverModule;
    address mTOFTReceiverModule;
    address tOFTMarketReceiverModule;
    address tOFTOptionsReceiverModule;
    address tOFTGenericReceiverModule;
    address toftHelper;
}

struct Reports {
    TapiocaReport tapiocaReport;
    MagnetarReport magnetarReport;
    MagnetarDepsReport magnetarDepsReport;
    UtilitiesReport utilitiesReport;
    YieldboxReport yieldboxReport;
    UsdoModulesReport usdoModulesReport;
    UsdoMarketModulesReport usdoMarketModulesReport;
    UsdoReport usdoReport;
    SGLReport sglReport;
    PenroseReport penroseReport;
    BBReport bbReport;
    TOFTModulesReport toftModulesReport;
}
