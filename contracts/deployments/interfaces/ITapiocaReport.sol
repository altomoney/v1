// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct TapiocaReport {
    address magnetar;
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
    address magnetarLeverageModule;
    address magnetarAssetModule;
    address magnetarHelper;
    address simpleLeverageExecutor;
    address toftHelper;
    address zeroXSwapper;
    address multiTokenSender;
    address toeHelper;
    address cluster;
    address altoAdaptiveCurveIrm;
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
    address singularityLauncher;
    address bigBangLauncher;
}

struct MagnetarReport {
    address magnetar;
    address simpleLeverageExecutor;
}

struct MagnetarDepsReport {
    address magnetarHelper;
    address magnetarCollateralModule;
    address magnetarMintModule;
    address magnetarOptionModule;
    address magnetarLeverageModule;
}

struct UtilitiesReport {
    address tapiocaMulticall;
    address cluster;
    address toeHelper;
    address pauser;
    address zeroXSwapper;
    address multiTokenSender;
    address altoAdaptiveCurveIrm;
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
}

struct ExtExReport {
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
    address cluster;
    address tapToken;
    address usdoToken;
    address nativeWrappedToken;
    address owner;
    address singularityMaster;
    address bigbangMaster;
    address magnetar;
    address prevPenrose;
}

struct LauncherReport {
    address singularityLauncher;
    address bigBangLauncher;
}

struct Reports {
    TapiocaReport tapiocaReport;
    MagnetarReport magnetarReport;
    MagnetarDepsReport magnetarDepsReport;
    UtilitiesReport utilitiesReport;
    ExtExReport ExtExReport;
    UsdoModulesReport usdoModulesReport;
    UsdoMarketModulesReport usdoMarketModulesReport;
    UsdoReport usdoReport;
    SGLReport sglReport;
    PenroseReport penroseReport;
    BBReport bbReport;
    LauncherReport launcherReport;
}
