// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERPTransactionBatch} from "../libraries/ERPOutputWriter.sol";
import {ERPVaultQueuePlan} from "../libraries/ERPVaultQueue.sol";

enum BorrowMarketOffboardingPhase {
    BATCH_A_CONTAIN,
    BATCH_B_SET_FIXED_RATE_IRM,
    BATCH_B_REDUCE_LTV,
    BATCH_C_RECOVER
}

/// @notice Governance-approved urgency selected when the ERP is activated.
enum BorrowMarketOffboardingSeverity {
    MEDIUM,
    HIGH,
    CRITICAL
}

/// @notice Whether Batch B is executing a calendar step or one terminal hourly step.
enum BorrowMarketOffboardingSchedulePhase {
    SCHEDULED,
    TERMINAL
}

/// @notice Per-market inputs and simulation limits approved for one activation.
/// @dev Limit values are denominated in raw borrow-token assets (DUSD for ERP-OFFBOARD-02).
struct BorrowMarketOffboardingMarket {
    uint256 correctionRateSpy;
    uint256 fixedRateSpy;
    address leverage;
    uint256 ltvReduction;
    address market;
    uint256 maxBadDebtAssets;
    uint256 maxLiquidationFundingAssets;
    uint256 maxProtocolLossAssets;
    uint256 maxSupplierLossAssets;
}

/// @notice One affected Vault and its governance-approved simulation loss limit.
struct BorrowMarketOffboardingVault {
    address allocator;
    uint256 maxVaultLossAssets;
    address[] replacementMarkets;
    address vault;
}

/// @notice Per-market current-state outcomes produced by the Batch B fork simulation.
struct BorrowMarketOffboardingSimulationTotals {
    uint256 liquidationFundingAssets;
    uint256 badDebtAssets;
    uint256 supplierLossAssets;
    uint256 protocolLossAssets;
}

/// @notice Borrower candidates discovered from the lending subgraph for one market.
struct BorrowMarketOffboardingBorrowerMarket {
    address[] borrowers;
    address market;
}

/// @notice Simulation-approved activation and step inputs for one ERP run.
struct BorrowMarketOffboardingManifest {
    string activationId;
    BorrowMarketOffboardingSeverity severity;
    BorrowMarketOffboardingSchedulePhase schedulePhase;
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
    BorrowMarketOffboardingVault[] vaults;
    BorrowMarketOffboardingMarket[] markets;
}

/// @notice Shared current-chain infrastructure loaded from deployment output.
struct BorrowMarketOffboardingContracts {
    address timelock;
    address ownerFixedRateIrmFactory;
    address marketRegistry;
    address altoAdapter;
    address liquidationPeriphery;
}

/// @notice Minimal current-chain input required by the selected ERP phase.
struct BorrowMarketOffboardingInput {
    BorrowMarketOffboardingContracts contracts;
}

struct BatchAContainParams {
    address freezerSafe;
    BorrowMarketOffboardingMarket[] markets;
    BorrowMarketOffboardingVault[] vaults;
}

struct BatchBSetFixedRateIrmParams {
    address timelockSafe;
    address timelock;
    address ownerFixedRateIrmFactory;
    uint256 version;
    BorrowMarketOffboardingMarket[] markets;
}

struct BatchBReduceLtvParams {
    address timelockSafe;
    address timelock;
    uint256 aprFloorSpy;
    uint256 previousAprFloorSpy;
    uint256 lastStepExecutedAt;
    bytes32 lastOperationId;
    BorrowMarketOffboardingMarket[] markets;
}

struct BatchCRecoverParams {
    address timelockSafe;
    address timelock;
    address marketRegistry;
    address altoAdapter;
    address liquidationPeriphery;
    BorrowMarketOffboardingMarket[] markets;
    BorrowMarketOffboardingVault[] vaults;
}

struct BorrowMarketOffboardingReport {
    ERPTransactionBatch freezerBatch;
    ERPTransactionBatch[] vaultCuratorBatches;
    ERPVaultQueuePlan[] vaultAllocatorPlans;
    ERPTransactionBatch timelockBatch;
    uint256 timelockDelay;
    bytes32 predecessor;
}
