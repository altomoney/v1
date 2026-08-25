// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum BorrowMarketOffboardingPhase {
    DEPLOY_OWNER_FIXED_RATE_IRM_FACTORY,
    BATCH_A_CONTAIN,
    BATCH_B_SET_FIXED_RATE_IRM,
    BATCH_B_REDUCE_LTV,
    BATCH_C_RECOVER
}

/// @notice Operator-selected values for one ERP phase.
struct BorrowMarketOffboardingParams {
    BorrowMarketOffboardingPhase phase;
    address freezerSafe;
    address timelockSafe;
}

/// @notice Named current-chain contracts used to construct phase-specific arguments.
struct BorrowMarketOffboardingContracts {
    address timelock;
    address ownerFixedRateIrmFactory;
    address marketRegistry;
    address altoAdapter;
    address liquidationPeriphery;
    address dusdVault;
    address wbtcBorrowMarket;
    address cbbtcBorrowMarket;
    address susdeBorrowMarket;
    address syrupUsdcBorrowMarket;
    address paxgBorrowMarket;
    address wbtcBorrowLeverage;
    address cbbtcBorrowLeverage;
    address susdeBorrowLeverage;
    address syrupUsdcBorrowLeverage;
    address paxgBorrowLeverage;
}

/// @notice Minimal current-chain input required by the selected ERP phase.
struct BorrowMarketOffboardingInput {
    BorrowMarketOffboardingContracts contracts;
}

struct DeployOwnerFixedRateIrmFactoryParams {
    address timelock;
    address recordedFactory;
}

struct BatchAContainParams {
    address freezerSafe;
    address[] borrowMarkets;
    address[] affectedVaults;
}

struct BorrowMarketRateParams {
    address market;
    uint256 borrowRateSpy;
}

struct BatchBSetFixedRateIrmParams {
    address timelockSafe;
    address timelock;
    address ownerFixedRateIrmFactory;
    BorrowMarketRateParams[] markets;
}

struct BatchBReduceLtvParams {
    address timelockSafe;
    address timelock;
    BorrowMarketRateParams[] markets;
}

struct BatchCRecoverParams {
    address timelockSafe;
    address timelock;
    address marketRegistry;
    address altoAdapter;
    address liquidationPeriphery;
    address[] borrowMarkets;
    address[] leverages;
    address[] affectedVaults;
}

/// @notice Ordered calls to be submitted by `safe` directly or wrapped in one atomic Timelock batch.
struct BorrowMarketOffboardingBatch {
    address safe;
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

struct BorrowMarketOffboardingReport {
    BorrowMarketOffboardingBatch freezerBatch;
    BorrowMarketOffboardingBatch vaultCuratorBatch;
    BorrowMarketOffboardingBatch timelockBatch;
    uint256 timelockDelay;
}
