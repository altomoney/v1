// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERPTransactionBatch, ERPTransactionPlan} from "../libraries/ERPOutputWriter.sol";

enum VaultOffboardingPhase {
    BATCH_A_CONTAIN,
    BATCH_B_CORRECT,
    BATCH_C_RECOVER
}

enum VaultOffboardingSeverity {
    MEDIUM,
    HIGH,
    CRITICAL
}

enum VaultOffboardingAction {
    UPDATE_WITHDRAW_QUEUE,
    SUBMIT_REMOVAL,
    EXECUTE_REMOVAL,
    SUBMIT_RECOVERY_CAP,
    ACCEPT_RECOVERY_CAP
}

/// @notice Underlying-market borrower candidates fetched for monitoring, as in ERP-OFFBOARD-01/02.
struct VaultOffboardingBorrowerMarket {
    address[] borrowers;
    address market;
}

/// @dev JSON-decoded structs use alphabetical field order, as in ERP-OFFBOARD-01/02.
struct VaultOffboardingToken {
    uint256 approvedBalance;
    address recipient;
    address token;
}

/// @notice Exact position approval and individual limit for an exceptional removal.
/// @dev Fields follow JSON's alphabetical decoding order.
struct VaultOffboardingRemovalTarget {
    uint256 approvedExpectedAssets;
    uint256 approvedSupplyShares;
    address market;
    uint256 maxExceptionalRemovedAssets;
}

/// @notice Positive recovery cap and individual limit for a quarantined market.
/// @dev Fields follow JSON's alphabetical decoding order.
struct VaultOffboardingRecoveryTarget {
    address market;
    uint256 maxTemporaryCapAssets;
    uint256 recoveryCap;
}

/// @notice Exact residual position approved for Batch C; fields follow JSON's alphabetical decoding order.
struct VaultOffboardingClosureMarket {
    uint256 approvedExpectedAssets;
    uint256 approvedQuarantinedAssets;
    uint256 approvedSupplyShares;
    address market;
}

/// @notice Governance-approved inputs for one Vault and one operational phase.
struct VaultOffboardingManifest {
    string activationId;
    VaultOffboardingSeverity severity;
    uint256 t0;
    uint256 noticeAt;
    bool noticeWaived;
    string noticeWaiverReference;
    uint256 step;
    uint256 sourceBlock;
    uint256 deploymentId;
    address timelockSafe;
    address curatorSafe;
    address allocator;
    address vault;
    address[] markets;
    address[] shareholders;
    address[] allocatorsToRevoke;
    address[] quarantinedMarkets;
    address[] withdrawQueue;
    VaultOffboardingAction action;
    VaultOffboardingRemovalTarget[] removalTargets;
    VaultOffboardingRecoveryTarget[] recoveryTargets;
    uint256 maxLostAssets;
    uint256 maxQuarantinedAssets;
    uint256 maxExceptionalRemovedAssets;
    uint256 maxTemporaryCapAssets;
    VaultOffboardingToken[] tokens;
    bool exceptionalClosure;
    string closureApprovalReference;
    string closureTreatmentReference;
    uint256 approvedTotalSupply;
    uint256 approvedTotalAssets;
    uint256 approvedLastTotalAssets;
    uint256 approvedLostAssets;
    VaultOffboardingClosureMarket[] closureMarkets;
}

struct VaultOffboardingContracts {
    address timelock;
    address vaultRegistry;
    address altoAdapter;
}

struct VaultOffboardingReport {
    ERPTransactionBatch curatorBatch;
    ERPTransactionBatch timelockBatch;
    ERPTransactionPlan allocatorPlan;
    uint256 timelockDelay;
    string closureOutcome;
}
