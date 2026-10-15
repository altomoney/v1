// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERPTransactionBatch} from "../libraries/ERPOutputWriter.sol";

enum MintMarketOffboardingPhase {
    BATCH_A_CONTAIN,
    BATCH_B_SET_FIXED_RATE_IRM,
    BATCH_B_REDUCE_LTV,
    BATCH_C_RECOVER
}

/// @notice Governance-approved urgency selected when ERP-OFFBOARD-01 is activated.
enum MintMarketOffboardingSeverity {
    MEDIUM,
    HIGH,
    CRITICAL
}

/// @notice Whether Batch B is executing a calendar step or one terminal hourly step.
enum MintMarketOffboardingSchedulePhase {
    SCHEDULED,
    TERMINAL
}

/// @notice One mint market and its governance-approved parameters across all offboarding phases.
/// @dev Field order is alphabetical so Foundry can decode the JSON object directly into this struct.
struct MintMarketOffboardingMarket {
    uint256 approvedRecoveryBadDebtAssets;
    uint256 correctionRateSpy;
    uint256 debtCeiling;
    uint256 dusdMinterCeiling;
    uint256 fixedRateSpy;
    address leverage;
    uint256 ltvReduction;
    address market;
    uint256 maxBadDebtAssets;
    uint256 maxDusdMintedAssets;
    uint256 maxLiquidationFundingAssets;
    uint256 maxSeizedCollateralAssets;
    uint256 maxUnbackedDusdAssets;
}

/// @notice Per-market outcomes produced by the Batch B fork simulation.
struct MintMarketOffboardingSimulationTotals {
    uint256 liquidationFundingAssets;
    uint256 badDebtAssets;
    uint256 seizedCollateralAssets;
    uint256 remainingBorrowedAssets;
    uint256 remainingDusdMintedAssets;
}

/// @notice Borrower candidates discovered from the lending subgraph for one market.
struct MintMarketOffboardingBorrowerMarket {
    address[] borrowers;
    address market;
}

/// @notice Reproducible inputs for one ERP-OFFBOARD-01 activation.
struct MintMarketOffboardingManifest {
    string activationId;
    MintMarketOffboardingSeverity severity;
    MintMarketOffboardingSchedulePhase schedulePhase;
    uint256 t0;
    uint256 step;
    uint256 lastExecutedStep;
    uint256 lastStepExecutedAt;
    bytes32 lastOperationId;
    uint256 sourceBlock;
    uint256 deploymentId;
    address freezerSafe;
    address timelockSafe;
    uint256 fixedRateIrmVersion;
    MintMarketOffboardingMarket[] markets;
}

/// @notice Current-chain infrastructure loaded from the selected deployment output.
struct MintMarketOffboardingContracts {
    address altoAdapter;
    address dusd;
    address liquidationPeriphery;
    address marketRegistry;
    address ownerFixedRateIrmFactory;
    address timelock;
}

struct MintMarketOffboardingInput {
    MintMarketOffboardingContracts contracts;
}

struct BatchBSetFixedRateIrmParams {
    address timelockSafe;
    address timelock;
    address ownerFixedRateIrmFactory;
    uint256 version;
    MintMarketOffboardingMarket[] markets;
}

struct BatchBReduceLtvParams {
    address timelockSafe;
    address timelock;
    address dusd;
    uint256 aprFloorSpy;
    uint256 previousAprFloorSpy;
    uint256 lastStepExecutedAt;
    bytes32 lastOperationId;
    MintMarketOffboardingMarket[] markets;
}

struct BatchCRecoverParams {
    address timelockSafe;
    address timelock;
    address dusd;
    address marketRegistry;
    address altoAdapter;
    address liquidationPeriphery;
    MintMarketOffboardingMarket[] markets;
}

struct MintMarketOffboardingReport {
    ERPTransactionBatch freezerBatch;
    ERPTransactionBatch timelockBatch;
    uint256 timelockDelay;
    bytes32 predecessor;
}
