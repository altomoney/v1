// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    VaultOffboardingAction,
    VaultOffboardingClosureMarket,
    VaultOffboardingContracts,
    VaultOffboardingManifest,
    VaultOffboardingPhase,
    VaultOffboardingRecoveryTarget,
    VaultOffboardingRemovalTarget,
    VaultOffboardingReport,
    VaultOffboardingSeverity
} from "./IVaultOffboarding.sol";
import {ERPOutputWriter, ERPTransactionBatch, ERPTransactionPlan} from "../libraries/ERPOutputWriter.sol";
import {ERPMarketOffboarding} from "../libraries/ERPMarketOffboarding.sol";
import {ERPVaultQueue} from "../libraries/ERPVaultQueue.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {ConstantsLib} from "@alto/lending/libraries/ConstantsLib.sol";
import {MarketConfig, PendingAddress, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Builds and writes operational phases for ERP-OFFBOARD-03, like the Mint/Borrow facades.
library VaultOffboarding {
    using AltoBalancesLib for address;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string internal constant ERP_OUTPUT_DIR = "ERP/ERP-OFFBOARD-03/output";

    /// @dev Validates the market scope, prepares the selected batch and writes its artifacts.
    function runPhase(
        VaultOffboardingPhase phase,
        VaultOffboardingManifest memory manifest,
        VaultOffboardingContracts memory contracts
    ) internal returns (VaultOffboardingReport memory report) {
        _validateMarketScope(manifest);
        if (phase == VaultOffboardingPhase.BATCH_A_CONTAIN) report = _prepareContainment(manifest, contracts);
        else if (phase == VaultOffboardingPhase.BATCH_B_CORRECT) report = _prepareCorrection(manifest, contracts);
        else if (phase == VaultOffboardingPhase.BATCH_C_RECOVER) report = _prepareRecovery(manifest, contracts);
        _writePhaseArtifacts(phase, manifest, contracts, report);
    }

    /// @dev Prepares the next Batch A stage: core containment, fee shutdown or allocator revocations.
    function _prepareContainment(VaultOffboardingManifest memory manifest, VaultOffboardingContracts memory contracts)
        private
        view
        returns (VaultOffboardingReport memory report)
    {
        IAltoVault vault = IAltoVault(manifest.vault);
        bytes[] memory ownerCalls = new bytes[](2);
        uint256 ownerCount;
        // Preserve the current guardian/timelock; revoke pending changes even after validAt has elapsed.
        if (vault.pendingGuardian().validAt != 0) {
            ownerCalls[ownerCount++] = abi.encodeCall(IAltoVaultBase.revokePendingGuardian, ());
        }
        if (vault.pendingTimelock().validAt != 0) {
            ownerCalls[ownerCount++] = abi.encodeCall(IAltoVaultBase.revokePendingTimelock, ());
        }
        report = _vaultTimelockReport(manifest, contracts, ownerCalls, ownerCount);

        bytes[] memory calls = new bytes[](manifest.markets.length * 3 + 1);
        uint256 count;
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            if (vault.pendingCap(market).validAt != 0) {
                calls[count++] = abi.encodeCall(IAltoVaultBase.revokePendingCap, (market));
            }
            if (vault.config(market).removableAt != 0) {
                calls[count++] = abi.encodeCall(IAltoVaultBase.revokePendingMarketRemoval, (market));
            }
        }
        if (vault.supplyQueueLength() != 0) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.setSupplyQueue, (new address[](0)));
        }
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            if (vault.config(market).cap == 0) continue;
            require(vault.marketRegistry().isBorrowMarket(market), "Batch A: cap reduction needs registered market");
            require(
                IMarket(market).borrowToken() == IERC4626(manifest.vault).asset(), "Batch A: inconsistent market asset"
            );
            calls[count++] = abi.encodeCall(IAltoVaultBase.submitCap, (market, 0));
        }
        if (count != 0) {
            _validateCurator(manifest);
            report.curatorBatch = _vaultBatch(manifest.curatorSafe, manifest.vault, calls, count);
        }
        // Verify applied containment from a fresh source block before preparing separate fee/role calls.
        if (ownerCount != 0 || count != 0) return report;
        if (vault.fee() != 0) {
            // setFee accrues the previous fee. Keep it separate from containment and role cleanup.
            calls = new bytes[](1);
            calls[0] = abi.encodeCall(IAltoVaultBase.setFee, (0));
            return _vaultTimelockReport(manifest, contracts, calls, 1);
        }
        calls = new bytes[](manifest.allocatorsToRevoke.length);
        count = _appendAllocatorRevocations(manifest, calls, 0);
        return _vaultTimelockReport(manifest, contracts, calls, count);
    }

    /// @dev Checks Batch B prerequisites and selects the requested queue, removal or recovery action.
    function _prepareCorrection(VaultOffboardingManifest memory manifest, VaultOffboardingContracts memory contracts)
        private
        view
        returns (VaultOffboardingReport memory)
    {
        _validateNotice(manifest);
        address[] memory targets = _actionMarkets(manifest);
        _validateCorrectionState(manifest, targets);
        if (manifest.action == VaultOffboardingAction.UPDATE_WITHDRAW_QUEUE) {
            // Prepare an ordinary queue update; funded markets must remain in the queue.
            address[] memory current = ERPVaultQueue.withdrawQueue(IAltoVault(manifest.vault));
            return _prepareQueueUpdate(manifest, contracts, current, targets);
        } else if (
            manifest.action == VaultOffboardingAction.SUBMIT_REMOVAL
                || manifest.action == VaultOffboardingAction.EXECUTE_REMOVAL
        ) {
            return _prepareMarketRemoval(manifest, contracts, targets);
        } else if (
            manifest.action == VaultOffboardingAction.SUBMIT_RECOVERY_CAP
                || manifest.action == VaultOffboardingAction.ACCEPT_RECOVERY_CAP
        ) {
            return _prepareRecoveryCap(manifest);
        } else {
            revert("Batch B: invalid action");
        }
    }

    /// @dev Submits pending removals or removes every approved target in one queue update after all delays elapse.
    function _prepareMarketRemoval(
        VaultOffboardingManifest memory manifest,
        VaultOffboardingContracts memory contracts,
        address[] memory targets
    ) private view returns (VaultOffboardingReport memory report) {
        IAltoVault vault = IAltoVault(manifest.vault);
        address[] memory current = ERPVaultQueue.withdrawQueue(vault);
        bytes[] memory calls = new bytes[](targets.length);
        uint256 count;
        for (uint256 i; i < targets.length; ++i) {
            address market = targets[i];
            MarketConfig memory config = vault.config(market);
            require(config.enabled, "Batch B: removal needs enabled market");
            require(ERPVaultQueue.contains(current, market), "Batch B: removal target outside queue");
            require(
                IMarket(market).position(manifest.vault).supplyShares != 0,
                "Batch B: use ordinary removal for empty market"
            );
            if (manifest.action == VaultOffboardingAction.SUBMIT_REMOVAL) {
                // Preserve existing removal timestamps when rerunning submission.
                if (config.removableAt == 0) {
                    calls[count++] = abi.encodeCall(IAltoVaultBase.submitMarketRemoval, (market));
                }
            } else if (manifest.action == VaultOffboardingAction.EXECUTE_REMOVAL) {
                require(
                    config.removableAt != 0 && block.timestamp >= config.removableAt,
                    "Batch B: market removal timelock not elapsed"
                );
                require(!ERPVaultQueue.contains(manifest.withdrawQueue, market), "Batch B: removal target retained");
            }
        }
        if (manifest.action == VaultOffboardingAction.SUBMIT_REMOVAL) {
            if (count == 0) return report;
            _validateCurator(manifest);
            report.curatorBatch = _vaultBatch(manifest.curatorSafe, manifest.vault, calls, count);
        } else if (manifest.action == VaultOffboardingAction.EXECUTE_REMOVAL) {
            // Validate the complete queue before projecting its combined accounting effects.
            report = _prepareQueueUpdate(manifest, contracts, current, targets);
            _validateExceptionalRemoval(manifest, targets);
        }
    }

    /// @dev Maps the approved market order to current queue indexes; only selected exceptions may omit funded markets.
    /// An unchanged queue produces no call.
    function _prepareQueueUpdate(
        VaultOffboardingManifest memory manifest,
        VaultOffboardingContracts memory contracts,
        address[] memory current,
        address[] memory exceptionalMarkets
    ) private view returns (VaultOffboardingReport memory report) {
        IAltoVault vault = IAltoVault(manifest.vault);
        uint256[] memory indexes = new uint256[](manifest.withdrawQueue.length);
        // Map the requested market order to current queue indexes; reject markets absent from the queue.
        for (uint256 i; i < indexes.length; ++i) {
            bool found;
            for (uint256 j; j < current.length; ++j) {
                if (current[j] == manifest.withdrawQueue[i]) {
                    indexes[i] = j;
                    found = true;
                    break;
                }
            }
            require(found, "Batch B: queue cannot add markets");
        }
        for (uint256 i; i < current.length; ++i) {
            if (ERPVaultQueue.contains(manifest.withdrawQueue, current[i])) continue;
            require(
                IMarket(current[i]).position(manifest.vault).supplyShares == 0
                    || ERPVaultQueue.contains(exceptionalMarkets, current[i]),
                "Batch B: ordinary funded market omitted"
            );
        }
        if (keccak256(abi.encode(current)) == keccak256(abi.encode(manifest.withdrawQueue))) return report;
        address allocator = manifest.allocator;
        require(
            allocator != address(0)
                && (allocator == Ownable(manifest.vault).owner()
                    || allocator == vault.curator()
                    || vault.isAllocator(allocator)),
            "Batch B: unauthorized allocator"
        );
        bytes memory data = abi.encodeCall(IAltoVaultBase.updateWithdrawQueue, (indexes));
        if (allocator == contracts.timelock) {
            bytes[] memory calls = new bytes[](1);
            calls[0] = data;
            return _vaultTimelockReport(manifest, contracts, calls, 1);
        }
        report.allocatorPlan = ERPTransactionPlan({
            caller: allocator,
            target: manifest.vault,
            data: data,
            functionName: "updateWithdrawQueue(uint256[])",
            argumentsJson: string.concat(
                "{\"indexes\":",
                ERPOutputWriter.uintArrayJson(indexes),
                ",\"markets\":",
                ERPOutputWriter.addressArrayJson(manifest.withdrawQueue),
                "}"
            ),
            postconditionsJson: "{}"
        });
    }

    /// @dev Checks each position approval, then bounds the combined removal, quarantine and loss amounts.
    function _validateExceptionalRemoval(VaultOffboardingManifest memory manifest, address[] memory targets)
        private
        view
    {
        IAltoVault vault = IAltoVault(manifest.vault);
        uint256 removedAssets;
        for (uint256 i; i < manifest.removalTargets.length; ++i) {
            VaultOffboardingRemovalTarget memory target = manifest.removalTargets[i];
            require(
                IMarket(target.market).position(manifest.vault).supplyShares == target.approvedSupplyShares
                    && target.market.expectedSupplyAssets(manifest.vault) == target.approvedExpectedAssets,
                "Batch B: position differs from approval"
            );
            require(
                target.approvedExpectedAssets <= target.maxExceptionalRemovedAssets, "Batch B: removal limit exceeded"
            );
            removedAssets += target.approvedExpectedAssets;
        }
        require(removedAssets <= manifest.maxExceptionalRemovedAssets, "Batch B: combined removal limit exceeded");
        uint256 remainingAssets;
        // Removal overwrites each target's quarantine record; retain other records without double counting.
        uint256 quarantine = removedAssets;
        for (uint256 i; i < manifest.markets.length; ++i) {
            if (!ERPVaultQueue.contains(targets, manifest.markets[i])) {
                quarantine += vault.quarantinedAssets(manifest.markets[i]);
            }
        }
        // The complete approved queue determines real assets after all selected removals.
        for (uint256 i; i < manifest.withdrawQueue.length; ++i) {
            remainingAssets += manifest.withdrawQueue[i].expectedSupplyAssets(manifest.vault);
        }
        // Project lost assets after removal, preserving any previously recorded loss.
        uint256 loss = Math.max(
            vault.lostAssets(),
            vault.lastTotalAssets() > remainingAssets ? vault.lastTotalAssets() - remainingAssets : 0
        );
        require(
            loss <= manifest.maxLostAssets && quarantine <= manifest.maxQuarantinedAssets,
            "Batch B: removal exceeds accounting limits"
        );
    }

    /// @dev Restores selected quarantined markets in manifest order; each acceptance is immediately followed by its reset.
    /// Already accepted caps are reset, and already completed recoveries produce no call.
    function _prepareRecoveryCap(VaultOffboardingManifest memory manifest)
        private
        view
        returns (VaultOffboardingReport memory report)
    {
        _validateCurator(manifest);
        IAltoVault vault = IAltoVault(manifest.vault);
        for (uint256 i; i < manifest.allocatorsToRevoke.length; ++i) {
            require(!vault.isAllocator(manifest.allocatorsToRevoke[i]), "Batch B: nonessential allocator remains");
        }
        bytes[] memory calls = new bytes[](manifest.recoveryTargets.length * 2);
        uint256 count;
        uint256 totalCap;
        uint256 newMarkets;
        address asset = IERC4626(manifest.vault).asset();
        for (uint256 i; i < manifest.recoveryTargets.length; ++i) {
            VaultOffboardingRecoveryTarget memory target = manifest.recoveryTargets[i];
            address market = target.market;
            MarketConfig memory config = vault.config(market);
            PendingUint192 memory pending = vault.pendingCap(market);
            require(
                target.recoveryCap != 0 && target.recoveryCap <= target.maxTemporaryCapAssets,
                "Batch B: recovery cap exceeds limit"
            );
            require(target.recoveryCap <= type(uint184).max, "Batch B: recovery cap overflows");
            require(vault.marketRegistry().isBorrowMarket(market), "Batch B: recovery needs registered market");
            require(IMarket(market).borrowToken() == asset, "Batch B: inconsistent market asset");
            require(ERPVaultQueue.contains(manifest.quarantinedMarkets, market), "Batch B: missing quarantine history");
            require(config.removableAt == 0, "Batch B: recovery market removal pending");
            // Bound the full approved cap budget, including targets already recovered on an earlier run.
            totalCap += target.recoveryCap;
            if (!config.enabled) ++newMarkets;

            if (manifest.action == VaultOffboardingAction.SUBMIT_RECOVERY_CAP) {
                // Common Batch B checks already require zero caps and no pending increases for submission.
                require(!config.enabled, "Batch B: recovery needs disabled market");
                calls[count++] = abi.encodeCall(IAltoVaultBase.submitCap, (market, target.recoveryCap));
            } else if (config.enabled) {
                require(
                    (config.cap == 0 || config.cap == target.recoveryCap) && pending.validAt == 0
                        && vault.quarantinedAssets(market) == 0,
                    "Batch B: unexpected accepted cap"
                );
                // Reset an already accepted cap; a zero cap means this recovery is complete.
                if (config.cap != 0) calls[count++] = abi.encodeCall(IAltoVaultBase.submitCap, (market, 0));
            } else {
                require(config.cap == 0, "Batch B: disabled recovery cap remains");
                require(
                    pending.value == target.recoveryCap && pending.validAt != 0 && block.timestamp >= pending.validAt,
                    "Batch B: recovery cap not ready"
                );
                // Keep each accept/reset pair adjacent in the same atomic Safe batch.
                calls[count++] = abi.encodeCall(IAltoVaultBase.acceptCap, (market));
                calls[count++] = abi.encodeCall(IAltoVaultBase.submitCap, (market, 0));
            }
        }
        require(totalCap <= manifest.maxTemporaryCapAssets, "Batch B: combined recovery cap limit exceeded");
        require(
            vault.withdrawQueueLength() + newMarkets <= ConstantsLib.MAX_QUEUE_LENGTH, "Batch B: withdrawal queue full"
        );
        report.curatorBatch = _vaultBatch(manifest.curatorSafe, manifest.vault, calls, count);
    }

    /// @dev Cleans approved residuals while retaining funded markets and recovery roles; integrations require zero shares.
    function _prepareRecovery(VaultOffboardingManifest memory manifest, VaultOffboardingContracts memory contracts)
        private
        view
        returns (VaultOffboardingReport memory report)
    {
        bool liveClaims = _validateRecoveryState(manifest);
        IAltoVault vault = IAltoVault(manifest.vault);
        bytes[] memory calls =
            new bytes[](manifest.tokens.length * 2 + manifest.allocatorsToRevoke.length + manifest.markets.length + 9);
        uint256 count = _appendRecoveryQueueCleanup(manifest, calls);
        address skimRecipient = vault.skimRecipient();
        for (uint256 i; i < manifest.tokens.length; ++i) {
            uint256 balance = IERC20(manifest.tokens[i].token).balanceOf(manifest.vault);
            if (balance == 0) continue;
            require(
                balance == manifest.tokens[i].approvedBalance && manifest.tokens[i].recipient != address(0),
                "Batch C: token treatment differs from approval"
            );
            if (skimRecipient != manifest.tokens[i].recipient) {
                skimRecipient = manifest.tokens[i].recipient;
                calls[count++] = abi.encodeCall(IAltoVaultBase.setSkimRecipient, (skimRecipient));
            }
            calls[count++] = abi.encodeCall(IAltoVaultBase.skim, (manifest.tokens[i].token));
        }
        if (skimRecipient != address(0)) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.setSkimRecipient, (address(0)));
        }
        if (vault.feeRecipient() != address(0)) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.setFeeRecipient, (address(0)));
        }
        count = _appendAllocatorRevocations(manifest, calls, count);
        if (!liveClaims && vault.curator() != address(0)) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.setCurator, (address(0)));
        }
        if (vault.pendingTimelock().validAt != 0) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.revokePendingTimelock, ());
        }
        PendingAddress memory pending = vault.pendingGuardian();
        if (pending.validAt != 0 && (liveClaims || pending.value != address(0) || vault.guardian() == address(0))) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.revokePendingGuardian, ());
        }
        if (!liveClaims && vault.guardian() != address(0) && (pending.validAt == 0 || pending.value != address(0))) {
            calls[count++] = abi.encodeCall(IAltoVaultBase.submitGuardian, (address(0)));
        }
        if (count != 0) {
            report = _vaultTimelockReport(manifest, contracts, calls, count);
            report.closureOutcome = liveClaims ? "partial-cleanup-prepared" : "full-cleanup-prepared";
            return report;
        }
        if (liveClaims) {
            report.closureOutcome = "residual-claims";
            return report;
        }
        // Integration removal remains in Batch C, after the cleanup is confirmed in current state.
        report = _prepareIntegrationRemoval(manifest, contracts);
        report.closureOutcome =
            report.timelockBatch.targets.length == 0 ? "no-cleanup-required" : "integration-removal-prepared";
    }

    /// @dev Retains funded entries in order and revokes removal permissions before omitting empty entries.
    function _appendRecoveryQueueCleanup(VaultOffboardingManifest memory manifest, bytes[] memory calls)
        private
        view
        returns (uint256 count)
    {
        IAltoVault vault = IAltoVault(manifest.vault);
        address[] memory current = ERPVaultQueue.withdrawQueue(vault);
        uint256[] memory indexes = new uint256[](current.length);
        uint256 kept;
        for (uint256 i; i < current.length; ++i) {
            if (IMarket(current[i]).position(manifest.vault).supplyShares != 0) {
                indexes[kept++] = i;
            }
        }
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            // Always revoke for omitted entries, so new supply before execution makes queue removal revert.
            if (
                vault.config(market).removableAt != 0
                    || (ERPVaultQueue.contains(current, market)
                        && IMarket(market).position(manifest.vault).supplyShares == 0)
            ) {
                calls[count++] = abi.encodeCall(IAltoVaultBase.revokePendingMarketRemoval, (market));
            }
        }
        if (kept != current.length) {
            assembly ("memory-safe") { mstore(indexes, kept) }
            calls[count++] = abi.encodeCall(IAltoVaultBase.updateWithdrawQueue, (indexes));
        }
    }

    /// @dev Accepts a ready guardian removal and removes the cleared Vault from its adapter and registry when needed.
    function _prepareIntegrationRemoval(
        VaultOffboardingManifest memory manifest,
        VaultOffboardingContracts memory contracts
    ) private view returns (VaultOffboardingReport memory report) {
        IAltoVault vault = IAltoVault(manifest.vault);
        // Reached only after this source state needs no queue, token or role cleanup.
        for (uint256 i; i < manifest.markets.length; ++i) {
            require(!vault.config(manifest.markets[i]).enabled, "Batch C: market config remains");
        }
        bool removeGuardian = vault.guardian() != address(0);
        bool removeAdapter = AdapterContractApproval(contracts.altoAdapter).isApprovedContract(manifest.vault);
        bool removeRegistry = IVaultRegistry(contracts.vaultRegistry).isVault(manifest.vault);
        (report.timelockBatch, report.timelockDelay) = ERPMarketOffboarding.newTimelockBatch(
            manifest.timelockSafe,
            contracts.timelock,
            (removeGuardian ? 1 : 0) + (removeAdapter ? 1 : 0) + (removeRegistry ? 1 : 0)
        );
        uint256 count;
        PendingAddress memory pending = vault.pendingGuardian();
        if (removeGuardian) {
            require(
                pending.value == address(0) && pending.validAt != 0 && block.timestamp >= pending.validAt,
                "Batch C: guardian removal not ready"
            );
            count = ERPOutputWriter.addBatchCall(
                report.timelockBatch, count, manifest.vault, abi.encodeCall(IAltoVaultBase.acceptGuardian, ())
            );
        } else {
            require(pending.validAt == 0, "Batch C: guardian change pending");
        }
        if (removeAdapter) {
            require(Ownable(contracts.altoAdapter).owner() == contracts.timelock, "Batch C: adapter owner mismatch");
            count = ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                count,
                contracts.altoAdapter,
                abi.encodeCall(AdapterContractApproval.revokeContract, (manifest.vault))
            );
        }
        if (removeRegistry) {
            require(Ownable(contracts.vaultRegistry).owner() == contracts.timelock, "Batch C: registry owner mismatch");
            count = ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                count,
                contracts.vaultRegistry,
                abi.encodeCall(IVaultRegistry.removeVault, (manifest.vault))
            );
        }
    }

    /// @dev The reviewed historical inventory must at least cover both current queues.
    function _validateMarketScope(VaultOffboardingManifest memory manifest) private view {
        IAltoVault vault = IAltoVault(manifest.vault);
        address[] memory supply = ERPVaultQueue.supplyQueue(vault);
        address[] memory withdrawal = ERPVaultQueue.withdrawQueue(vault);
        for (uint256 i; i < supply.length; ++i) {
            require(ERPVaultQueue.contains(manifest.markets, supply[i]), "ERP: supply market omitted");
        }
        for (uint256 i; i < withdrawal.length; ++i) {
            require(ERPVaultQueue.contains(manifest.markets, withdrawal[i]), "ERP: withdrawal market omitted");
        }
    }

    /// @dev Build one ordered address list for scope checks and reuse it for queue and containment membership.
    function _actionMarkets(VaultOffboardingManifest memory manifest) private pure returns (address[] memory targets) {
        if (
            manifest.action == VaultOffboardingAction.SUBMIT_REMOVAL
                || manifest.action == VaultOffboardingAction.EXECUTE_REMOVAL
        ) {
            targets = new address[](manifest.removalTargets.length);
            for (uint256 i; i < targets.length; ++i) {
                targets[i] = manifest.removalTargets[i].market;
            }
        } else if (
            manifest.action == VaultOffboardingAction.SUBMIT_RECOVERY_CAP
                || manifest.action == VaultOffboardingAction.ACCEPT_RECOVERY_CAP
        ) {
            targets = new address[](manifest.recoveryTargets.length);
            for (uint256 i; i < targets.length; ++i) {
                targets[i] = manifest.recoveryTargets[i].market;
            }
        } else {
            return new address[](0);
        }
        for (uint256 i; i < targets.length; ++i) {
            require(targets[i] != address(0), "Batch B: zero action market");
            require(ERPVaultQueue.contains(manifest.markets, targets[i]), "Batch B: action market outside scope");
            for (uint256 j; j < i; ++j) {
                require(targets[j] != targets[i], "Batch B: duplicate action market");
            }
        }
    }

    /// @dev Common to all Batch B severities. Recovery acceptance validates every selected cap in its own builder.
    function _validateCorrectionState(VaultOffboardingManifest memory manifest, address[] memory targets) private view {
        IAltoVault vault = IAltoVault(manifest.vault);
        require(vault.supplyQueueLength() == 0, "Batch B: supply queue remains");
        require(vault.fee() == 0, "Batch B: fee remains");
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            // Only selected recoveries may have pending or accepted caps; no unselected cap can remain open.
            if (
                manifest.action == VaultOffboardingAction.ACCEPT_RECOVERY_CAP && ERPVaultQueue.contains(targets, market)
            ) {
                continue;
            }
            require(
                vault.config(market).cap == 0 && vault.pendingCap(market).validAt == 0,
                "Batch B: allocation capacity remains"
            );
        }
    }

    /// @dev Requires containment and either zero claims or exact exceptional approvals; live claims retain recovery routes.
    function _validateRecoveryState(VaultOffboardingManifest memory manifest) private view returns (bool liveClaims) {
        IAltoVault vault = IAltoVault(manifest.vault);
        require(vault.supplyQueueLength() == 0 && vault.fee() == 0, "Batch C: containment incomplete");
        if (manifest.exceptionalClosure) {
            liveClaims = _validateExceptionalClosure(manifest);
        } else {
            require(IERC4626(manifest.vault).totalSupply() == 0, "Batch C: shareholder claims remain");
            require(
                IERC4626(manifest.vault).totalAssets() == 0 && vault.lastTotalAssets() == 0 && vault.lostAssets() == 0,
                "Batch C: unresolved accounting"
            );
        }
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            if (!manifest.exceptionalClosure) {
                require(
                    IMarket(market).position(manifest.vault).supplyShares == 0 && vault.quarantinedAssets(market) == 0,
                    "Batch C: market claims remain"
                );
            }
            require(
                vault.config(market).cap == 0 && vault.pendingCap(market).validAt == 0,
                "Batch C: allocation capacity remains"
            );
        }
    }

    /// @dev Matches the complete approved snapshot and bounds recorded quarantine plus stored/calculated losses.
    function _validateExceptionalClosure(VaultOffboardingManifest memory manifest)
        private
        view
        returns (bool liveClaims)
    {
        IAltoVault vault = IAltoVault(manifest.vault);
        uint256 totalSupply = IERC4626(manifest.vault).totalSupply();
        uint256 totalAssets = IERC4626(manifest.vault).totalAssets();
        require(
            totalSupply == manifest.approvedTotalSupply && totalAssets == manifest.approvedTotalAssets
                && vault.lastTotalAssets() == manifest.approvedLastTotalAssets
                && vault.lostAssets() == manifest.approvedLostAssets,
            "Batch C: accounting differs from approval"
        );
        liveClaims = totalSupply != 0;
        address[] memory queue = ERPVaultQueue.withdrawQueue(vault);
        uint256 realAssets;
        uint256 quarantine;
        for (uint256 i; i < manifest.closureMarkets.length; ++i) {
            VaultOffboardingClosureMarket memory approval = manifest.closureMarkets[i];
            uint256 shares = IMarket(approval.market).position(manifest.vault).supplyShares;
            uint256 assets = approval.market.expectedSupplyAssets(manifest.vault);
            uint256 recorded = vault.quarantinedAssets(approval.market);
            require(
                shares == approval.approvedSupplyShares && assets == approval.approvedExpectedAssets
                    && recorded == approval.approvedQuarantinedAssets,
                "Batch C: market position differs from approval"
            );
            liveClaims = liveClaims || shares != 0;
            quarantine += recorded;
            if (ERPVaultQueue.contains(queue, approval.market)) realAssets += assets;
        }
        require(
            manifest.approvedLostAssets <= manifest.maxLostAssets && totalAssets - realAssets <= manifest.maxLostAssets,
            "Batch C: loss exceeds limit"
        );
        require(quarantine <= manifest.maxQuarantinedAssets, "Batch C: quarantine exceeds limit");
    }

    /// @dev Checks the manifest's notice timing or waiver reference for the selected Batch B severity.
    function _validateNotice(VaultOffboardingManifest memory manifest) private view {
        require(block.timestamp >= manifest.t0, "Batch B: before T0");
        if (manifest.severity == VaultOffboardingSeverity.MEDIUM) {
            require(
                !manifest.noticeWaived && manifest.noticeAt != 0 && manifest.noticeAt <= manifest.t0
                    && manifest.t0 - manifest.noticeAt >= 7 days,
                "Batch B: Medium notice missing"
            );
        } else if (manifest.severity == VaultOffboardingSeverity.HIGH) {
            if (manifest.noticeWaived) {
                require(bytes(manifest.noticeWaiverReference).length != 0, "Batch B: waiver reference missing");
            } else {
                require(manifest.noticeAt != 0 && manifest.noticeAt <= manifest.t0, "Batch B: notice missing");
                require(manifest.t0 - manifest.noticeAt >= 1 days, "Batch B: High notice too short");
            }
        } else if (manifest.severity == VaultOffboardingSeverity.CRITICAL) {
            if (manifest.noticeWaived) {
                require(bytes(manifest.noticeWaiverReference).length != 0, "Batch B: waiver reference missing");
            } else {
                require(manifest.noticeAt != 0 && manifest.noticeAt <= manifest.t0, "Batch B: notice missing");
            }
        }
    }

    /// @dev Confirms the configured Safe is the Vault's current curator.
    function _validateCurator(VaultOffboardingManifest memory manifest) private view {
        require(
            manifest.curatorSafe != address(0) && manifest.curatorSafe == IAltoVault(manifest.vault).curator(),
            "ERP: unauthorized curator Safe"
        );
    }

    /// @dev Appends revocations for active allocators in the manifest and returns the updated call count.
    function _appendAllocatorRevocations(VaultOffboardingManifest memory manifest, bytes[] memory calls, uint256 count)
        private
        view
        returns (uint256)
    {
        for (uint256 i; i < manifest.allocatorsToRevoke.length; ++i) {
            address allocator = manifest.allocatorsToRevoke[i];
            if (IAltoVault(manifest.vault).isAllocator(allocator)) {
                calls[count++] = abi.encodeCall(IAltoVaultBase.setIsAllocator, (allocator, false));
            }
        }
        return count;
    }

    /// @dev Builds an owner Timelock batch for the populated Vault calls, or an empty report when none are needed.
    function _vaultTimelockReport(
        VaultOffboardingManifest memory manifest,
        VaultOffboardingContracts memory contracts,
        bytes[] memory calls,
        uint256 count
    ) private view returns (VaultOffboardingReport memory report) {
        if (count == 0) return report;
        require(Ownable(manifest.vault).owner() == contracts.timelock, "ERP: Vault owner mismatch");
        require(manifest.timelockSafe.code.length != 0, "ERP: missing Timelock Safe");
        report.timelockBatch = _vaultBatch(manifest.timelockSafe, manifest.vault, calls, count);
        report.timelockDelay = TimelockController(payable(contracts.timelock)).getMinDelay();
    }

    /// @dev Builds a Safe batch containing the populated direct Vault calls.
    function _vaultBatch(address safe, address vault, bytes[] memory calls, uint256 count)
        private
        pure
        returns (ERPTransactionBatch memory batch)
    {
        batch = ERPOutputWriter.newBatch(safe, count);
        for (uint256 i; i < count; ++i) {
            ERPOutputWriter.addBatchCall(batch, i, vault, calls[i]);
        }
    }

    /// @dev Writes the available Safe, allocator and Timelock artifacts with a deterministic run-specific salt.
    function _writePhaseArtifacts(
        VaultOffboardingPhase phase,
        VaultOffboardingManifest memory manifest,
        VaultOffboardingContracts memory contracts,
        VaultOffboardingReport memory report
    ) private {
        bytes32 salt = keccak256(
            abi.encode(
                block.chainid,
                manifest.vault,
                manifest.activationId,
                phase,
                phase == VaultOffboardingPhase.BATCH_B_CORRECT ? uint256(manifest.action) : 0,
                manifest.step,
                manifest.sourceBlock
            )
        );
        string memory directory = artifactDirectory(phase, manifest);
        vm.createDir(directory, true);
        ERPOutputWriter.writeOptionalSafeBatch(
            directory, "vault-curator-safe.json", "ERP-OFFBOARD-03 - Vault Curator", report.curatorBatch
        );
        ERPOutputWriter.writeOptionalTransactionPlan(
            directory, "vault-allocator.json", manifest.sourceBlock, report.allocatorPlan
        );
        ERPOutputWriter.writeOptionalTimelockPair(
            directory,
            "vault-governance",
            "ERP-OFFBOARD-03 - Vault Governance",
            contracts.timelock,
            report.timelockBatch,
            report.timelockDelay,
            bytes32(0),
            salt
        );
    }

    /// @dev Groups artifacts by activation, phase, run and source block, with a separate directory per Batch B action.
    function artifactDirectory(VaultOffboardingPhase phase, VaultOffboardingManifest memory manifest)
        internal
        pure
        returns (string memory)
    {
        string memory directory = string.concat(
            ERP_OUTPUT_DIR,
            "/",
            manifest.activationId,
            "/phase-",
            vm.toString(uint256(phase)),
            "/step-",
            vm.toString(manifest.step),
            "/source-block-",
            vm.toString(manifest.sourceBlock)
        );
        if (phase == VaultOffboardingPhase.BATCH_B_CORRECT) {
            directory = string.concat(directory, "/action-", vm.toString(uint256(manifest.action)));
        }
        return directory;
    }
}

