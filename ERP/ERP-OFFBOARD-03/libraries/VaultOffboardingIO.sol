// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    VaultOffboardingAction,
    VaultOffboardingBorrowerMarket,
    VaultOffboardingClosureMarket,
    VaultOffboardingContracts,
    VaultOffboardingManifest,
    VaultOffboardingPhase,
    VaultOffboardingRecoveryTarget,
    VaultOffboardingRemovalTarget,
    VaultOffboardingReport,
    VaultOffboardingSeverity,
    VaultOffboardingToken
} from "../IVaultOffboarding.sol";
import {ERPMarketOffboardingIO} from "../../libraries/ERPMarketOffboardingIO.sol";
import {ERPVaultQueue} from "../../libraries/ERPVaultQueue.sol";
import {IAltoVault} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {MarketConfig, PendingAddress, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Manifest loading and source-state reporting, following the other offboarding IO libraries.
library VaultOffboardingIO {
    using AltoBalancesLib for address;

    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Common identity and reporting inputs; no execution schedule or phase-specific approvals.
    function loadActivationManifest(string memory json)
        internal
        view
        returns (VaultOffboardingManifest memory manifest)
    {
        manifest.activationId = VM.parseJsonString(json, ".activationId");
        manifest.severity = VaultOffboardingSeverity(VM.parseJsonUint(json, ".severity"));
        manifest.t0 = VM.parseJsonUint(json, ".t0");
        manifest.step = VM.parseJsonUint(json, ".step");
        manifest.sourceBlock = VM.parseJsonUint(json, ".sourceBlock");
        manifest.deploymentId = VM.parseJsonUint(json, ".deploymentId");
        manifest.vault = VM.parseJsonAddress(json, ".vault");
        manifest.markets = VM.parseJsonAddressArray(json, ".markets");
        manifest.shareholders = VM.parseJsonAddressArray(json, ".shareholders");
        manifest.quarantinedMarkets = VM.parseJsonAddressArray(json, ".quarantinedMarkets");
        // Optional for reports; required when a phase revokes or checks these permissions.
        if (VM.keyExistsJson(json, ".allocatorsToRevoke")) {
            manifest.allocatorsToRevoke = VM.parseJsonAddressArray(json, ".allocatorsToRevoke");
        }
        _validateIdentity(manifest);
    }

    /// @notice Populate only inputs consumed by the selected phase/action.
    function loadPhaseParameters(
        string memory json,
        VaultOffboardingPhase phase,
        VaultOffboardingManifest memory manifest
    ) internal view {
        manifest.timelockSafe = ERPMarketOffboardingIO.tryParseAddress(json, ".timelockSafe");
        if (phase == VaultOffboardingPhase.BATCH_A_CONTAIN) {
            manifest.curatorSafe = VM.parseJsonAddress(json, ".curatorSafe");
            require(VM.keyExistsJson(json, ".allocatorsToRevoke"), "ERP manifest: missing allocator list");
        } else if (phase == VaultOffboardingPhase.BATCH_C_RECOVER) {
            require(VM.keyExistsJson(json, ".allocatorsToRevoke"), "ERP manifest: missing allocator list");
            manifest.tokens = abi.decode(VM.parseJson(json, ".tokens"), (VaultOffboardingToken[]));
            _validateTokens(manifest);
            if (VM.keyExistsJson(json, ".exceptionalClosure")) {
                manifest.exceptionalClosure = VM.parseJsonBool(json, ".exceptionalClosure");
            }
            if (manifest.exceptionalClosure) _loadExceptionalClosure(json, manifest);
        } else {
            manifest.noticeAt = VM.parseJsonUint(json, ".noticeAt");
            manifest.noticeWaived = VM.parseJsonBool(json, ".noticeWaived");
            if (manifest.noticeWaived) {
                manifest.noticeWaiverReference = VM.parseJsonString(json, ".noticeWaiverReference");
            }
            VaultOffboardingAction action = manifest.action;
            if (
                action == VaultOffboardingAction.UPDATE_WITHDRAW_QUEUE
                    || action == VaultOffboardingAction.EXECUTE_REMOVAL
            ) {
                manifest.allocator = VM.parseJsonAddress(json, ".allocator");
                manifest.withdrawQueue = VM.parseJsonAddressArray(json, ".withdrawQueue");
                _unique(manifest.withdrawQueue);
            } else {
                manifest.curatorSafe = VM.parseJsonAddress(json, ".curatorSafe");
            }
            if (action == VaultOffboardingAction.SUBMIT_REMOVAL || action == VaultOffboardingAction.EXECUTE_REMOVAL) {
                manifest.removalTargets = _loadRemovalTargets(json, action == VaultOffboardingAction.EXECUTE_REMOVAL);
            }
            if (action == VaultOffboardingAction.EXECUTE_REMOVAL) {
                manifest.maxLostAssets = VM.parseJsonUint(json, ".maxLostAssets");
                manifest.maxQuarantinedAssets = VM.parseJsonUint(json, ".maxQuarantinedAssets");
                manifest.maxExceptionalRemovedAssets = VM.parseJsonUint(json, ".maxExceptionalRemovedAssets");
            }
            if (
                action == VaultOffboardingAction.SUBMIT_RECOVERY_CAP
                    || action == VaultOffboardingAction.ACCEPT_RECOVERY_CAP
            ) {
                manifest.recoveryTargets =
                    abi.decode(VM.parseJson(json, ".recoveryTargets"), (VaultOffboardingRecoveryTarget[]));
                require(manifest.recoveryTargets.length != 0, "ERP manifest: no action targets");
                manifest.maxTemporaryCapAssets = VM.parseJsonUint(json, ".maxTemporaryCapAssets");
                require(VM.keyExistsJson(json, ".allocatorsToRevoke"), "ERP manifest: missing allocator list");
            }
        }
    }

    /// @dev Exceptional approvals cover the full reviewed inventory, including zero positions.
    function _loadExceptionalClosure(string memory json, VaultOffboardingManifest memory manifest) private view {
        manifest.closureApprovalReference = VM.parseJsonString(json, ".closureApprovalReference");
        manifest.closureTreatmentReference = VM.parseJsonString(json, ".closureTreatmentReference");
        require(bytes(manifest.closureApprovalReference).length != 0, "Batch C: closure approval reference missing");
        require(bytes(manifest.closureTreatmentReference).length != 0, "Batch C: closure treatment reference missing");
        manifest.approvedTotalSupply = VM.parseJsonUint(json, ".approvedTotalSupply");
        manifest.approvedTotalAssets = VM.parseJsonUint(json, ".approvedTotalAssets");
        manifest.approvedLastTotalAssets = VM.parseJsonUint(json, ".approvedLastTotalAssets");
        manifest.approvedLostAssets = VM.parseJsonUint(json, ".approvedLostAssets");
        manifest.maxLostAssets = VM.parseJsonUint(json, ".maxLostAssets");
        manifest.maxQuarantinedAssets = VM.parseJsonUint(json, ".maxQuarantinedAssets");
        manifest.closureMarkets = abi.decode(VM.parseJson(json, ".closureMarkets"), (VaultOffboardingClosureMarket[]));
        require(manifest.closureMarkets.length == manifest.markets.length, "Batch C: closure inventory incomplete");
        for (uint256 i; i < manifest.closureMarkets.length; ++i) {
            address market = manifest.closureMarkets[i].market;
            require(market != address(0), "Batch C: zero closure market");
            require(ERPVaultQueue.contains(manifest.markets, market), "Batch C: closure market outside scope");
            for (uint256 j; j < i; ++j) {
                require(market != manifest.closureMarkets[j].market, "Batch C: duplicate closure market");
            }
        }
    }

    /// @dev Submission needs only market addresses; execution requires fresh approvals and individual limits.
    function _loadRemovalTargets(string memory json, bool execution)
        private
        view
        returns (VaultOffboardingRemovalTarget[] memory targets)
    {
        if (execution) {
            targets = abi.decode(VM.parseJson(json, ".removalTargets"), (VaultOffboardingRemovalTarget[]));
            require(targets.length != 0, "ERP manifest: no action targets");
            return targets;
        }
        targets = new VaultOffboardingRemovalTarget[](_targetCount(json, ".removalTargets"));
        for (uint256 i; i < targets.length; ++i) {
            targets[i].market = VM.parseJsonAddress(json, string.concat(".removalTargets[", VM.toString(i), "].market"));
        }
    }

    /// @dev Count entries themselves so a malformed row cannot be skipped by an address-only JSONPath query.
    function _targetCount(string memory json, string memory key) private view returns (uint256 count) {
        while (VM.keyExistsJson(json, string.concat(key, "[", VM.toString(count), "]"))) {
            ++count;
        }
        require(count != 0, "ERP manifest: no action targets");
    }

    function loadCurrentChainContracts(uint256 deploymentId)
        internal
        view
        returns (VaultOffboardingContracts memory contracts)
    {
        string memory json = VM.readFile(
            string.concat(ERPMarketOffboardingIO.deploymentFolder(block.chainid, deploymentId), "/addresses.json")
        );
        contracts.timelock = VM.parseJsonAddress(json, ".contracts.timelock");
        contracts.vaultRegistry = VM.parseJsonAddress(json, ".contracts.vaultRegistry");
        contracts.altoAdapter = VM.parseJsonAddress(json, ".contracts.altoAdapter");
    }

    /// @notice Preparation outcome and supplied evidence references, not a certificate of settlement or formal closure.
    function appendClosureOutcome(
        string memory directory,
        VaultOffboardingManifest memory manifest,
        VaultOffboardingReport memory report
    ) internal {
        string memory key = "vault-closure";
        VM.serializeBool(key, "exceptionalClosure", manifest.exceptionalClosure);
        VM.serializeString(key, "outcome", report.closureOutcome);
        VM.serializeString(key, "closureApprovalReference", manifest.closureApprovalReference);
        string memory json = VM.serializeString(key, "closureTreatmentReference", manifest.closureTreatmentReference);
        VM.writeJson(json, string.concat(directory, "/exposure-report.json"), ".closure");
    }

    function _writeBorrowerList(
        string memory manifestPath,
        VaultOffboardingManifest memory manifest,
        string memory directory
    ) private returns (VaultOffboardingBorrowerMarket[] memory markets) {
        VM.createDir(directory, true);
        string[] memory command =
            ERPMarketOffboardingIO.borrowerFetcherCommand(manifestPath, string.concat(directory, "/borrowers.json"));
        string memory json = string(VM.ffi(command));
        require(VM.parseJsonUint(json, ".chainId") == block.chainid, "Monitoring: borrower chain mismatch");
        require(VM.parseJsonUint(json, ".sourceBlock") == manifest.sourceBlock, "Monitoring: borrower block mismatch");
        markets = abi.decode(VM.parseJson(json, ".markets"), (VaultOffboardingBorrowerMarket[]));
        require(markets.length == manifest.markets.length, "Monitoring: borrower markets mismatch");
        for (uint256 i; i < markets.length; ++i) {
            require(markets[i].market == manifest.markets[i], "Monitoring: borrower market mismatch");
        }
    }

    function writeBorrowerReport(
        string memory manifestPath,
        VaultOffboardingManifest memory manifest,
        string memory directory
    ) internal {
        VaultOffboardingBorrowerMarket[] memory markets = _writeBorrowerList(manifestPath, manifest, directory);
        string memory borrowers = "[";
        for (uint256 i; i < markets.length; ++i) {
            for (uint256 j; j < markets[i].borrowers.length; ++j) {
                borrowers = string.concat(
                    borrowers,
                    bytes(borrowers).length == 1 ? "" : ",",
                    _borrowerPositionJson(markets[i].market, markets[i].borrowers[j])
                );
            }
        }
        VM.writeJson(string.concat(borrowers, "]"), string.concat(directory, "/exposure-report.json"), ".borrowers");
    }

    /// @notice Observed source state only; this report does not certify a transaction or economic simulation.
    function writeExposureReport(string memory directory, VaultOffboardingManifest memory manifest) internal {
        IAltoVault vault = IAltoVault(manifest.vault);
        string memory key = "vault-exposure";
        VM.serializeUint(key, "sourceBlock", manifest.sourceBlock);
        VM.serializeUint(key, "sourceTimestamp", block.timestamp);
        VM.serializeAddress(key, "vault", manifest.vault);
        _amount(key, "totalSupply", IERC4626(manifest.vault).totalSupply());
        {
            uint256 totalAssets = IERC4626(manifest.vault).totalAssets();
            _amount(key, "totalAssets", totalAssets);
            uint256 realAssets;
            address[] memory queue = ERPVaultQueue.withdrawQueue(vault);
            for (uint256 i; i < queue.length; ++i) {
                realAssets += queue[i].expectedSupplyAssets(manifest.vault);
            }
            _amount(key, "calculatedLostAssets", totalAssets - realAssets);
        }
        _amount(key, "lastTotalAssets", vault.lastTotalAssets());
        _amount(key, "lostAssets", vault.lostAssets());
        _amount(key, "fee", vault.fee());
        _amount(key, "directUnderlyingAssets", IERC20(IERC4626(manifest.vault).asset()).balanceOf(manifest.vault));
        VM.serializeAddress(key, "supplyQueue", ERPVaultQueue.supplyQueue(vault));
        VM.serializeAddress(key, "withdrawQueue", ERPVaultQueue.withdrawQueue(vault));
        VM.serializeAddress(key, "quarantinedMarkets", manifest.quarantinedMarkets);
        _serializeRoles(key, vault, manifest);
        {
            uint256[] memory checkpoints = _checkpointTimestamps(manifest);
            VM.serializeUint(key, "checkpointTimestamps", checkpoints);
            VM.serializeBool(key, "activeWindowElapsed", block.timestamp >= checkpoints[checkpoints.length - 1]);
        }
        string memory json =
            VM.serializeString(key, "liquidityLabel", "estimated available; not reserved or guaranteed");
        VM.createDir(directory, true);
        string memory path = string.concat(directory, "/exposure-report.json");
        VM.writeJson(json, path);
        {
            string memory markets = "[";
            for (uint256 i; i < manifest.markets.length; ++i) {
                markets = string.concat(markets, i == 0 ? "" : ",", _marketJson(manifest.vault, manifest.markets[i]));
            }
            VM.writeJson(string.concat(markets, "]"), path, ".markets");
        }
        {
            string memory holders = "[";
            for (uint256 i; i < manifest.shareholders.length; ++i) {
                holders = string.concat(
                    holders, i == 0 ? "" : ",", _shareholderJson(manifest.vault, manifest.shareholders[i])
                );
            }
            VM.writeJson(string.concat(holders, "]"), path, ".shareholders");
        }
        string memory tokens = "[";
        for (uint256 i; i < manifest.tokens.length; ++i) {
            string memory tokenKey = "vault-token";
            VM.serializeAddress(tokenKey, "token", manifest.tokens[i].token);
            string memory tokenJson =
                _amount(tokenKey, "balance", IERC20(manifest.tokens[i].token).balanceOf(manifest.vault));
            tokens = string.concat(tokens, i == 0 ? "" : ",", tokenJson);
        }
        VM.writeJson(string.concat(tokens, "]"), path, ".tokens");
    }

    function _serializeRoles(string memory key, IAltoVault vault, VaultOffboardingManifest memory manifest) private {
        VM.serializeAddress(key, "owner", AltoOwnable2Step(manifest.vault).owner());
        VM.serializeAddress(key, "pendingOwner", AltoOwnable2Step(manifest.vault).pendingOwner());
        VM.serializeAddress(key, "curator", vault.curator());
        VM.serializeAddress(key, "guardian", vault.guardian());
        VM.serializeAddress(key, "feeRecipient", vault.feeRecipient());
        VM.serializeAddress(key, "skimRecipient", vault.skimRecipient());
        VM.serializeAddress(key, "marketRegistry", address(vault.marketRegistry()));
        VM.serializeUint(key, "vaultTimelock", vault.timelock());
        PendingAddress memory guardian = vault.pendingGuardian();
        VM.serializeAddress(key, "pendingGuardian", guardian.value);
        VM.serializeUint(key, "pendingGuardianAt", guardian.validAt);
        PendingUint192 memory timelock = vault.pendingTimelock();
        VM.serializeUint(key, "pendingTimelock", timelock.value);
        VM.serializeUint(key, "pendingTimelockAt", timelock.validAt);
        VM.serializeAddress(key, "allocatorsToRevoke", manifest.allocatorsToRevoke);
        bool[] memory active = new bool[](manifest.allocatorsToRevoke.length);
        for (uint256 i; i < active.length; ++i) {
            active[i] = vault.isAllocator(manifest.allocatorsToRevoke[i]);
        }
        VM.serializeBool(key, "allocatorPermissionsActive", active);
    }

    /// @dev These are reporting dates, never transaction eligibility gates.
    function _checkpointTimestamps(VaultOffboardingManifest memory manifest)
        private
        pure
        returns (uint256[] memory times)
    {
        if (manifest.severity == VaultOffboardingSeverity.CRITICAL) {
            times = new uint256[](8);
            for (uint256 i; i < times.length; ++i) {
                times[i] = manifest.t0 + i * 1 days;
            }
        } else {
            uint256[6] memory daysFromT0 = manifest.severity == VaultOffboardingSeverity.MEDIUM
                ? [uint256(0), 1, 7, 14, 21, 28]
                : [uint256(0), 1, 4, 7, 10, 14];
            times = new uint256[](6);
            for (uint256 i; i < times.length; ++i) {
                times[i] = manifest.t0 + daysFromT0[i] * 1 days;
            }
        }
    }

    function _marketJson(address vaultAddress, address market) private returns (string memory) {
        IAltoVault vault = IAltoVault(vaultAddress);
        MarketConfig memory config = vault.config(market);
        string memory key = "vault-market";
        VM.serializeAddress(key, "market", market);
        VM.serializeAddress(key, "feeRecipient", IMarket(market).feeRecipient());
        VM.serializeAddress(key, "irm", IMarket(market).irm());
        VM.serializeBool(key, "registered", vault.marketRegistry().isBorrowMarket(market));
        VM.serializeBool(key, "paused", IMarket(market).paused(PAUSE_TYPE));
        VM.serializeBool(key, "frozen", IMarket(market).paused(FROZEN_TYPE));
        _amount(key, "supplyShares", IMarket(market).position(vaultAddress).supplyShares);
        {
            (uint256 supply,, uint256 borrowed,) = market.expectedMarketBalances();
            uint256 balance = IERC20(IMarket(market).borrowToken()).balanceOf(market);
            uint256 assets = market.expectedSupplyAssets(vaultAddress);
            uint256 liquidity = Math.min(supply > borrowed ? supply - borrowed : 0, balance);
            _amount(key, "marketAvailableLiquidity", liquidity);
            liquidity = IMarket(market).paused(PAUSE_TYPE) || !config.enabled ? 0 : Math.min(assets, liquidity);
            _amount(key, "expectedSupplyAssets", assets);
            _amount(key, "totalSupplyAssets", supply);
            _amount(key, "totalBorrowAssets", borrowed);
            _amount(key, "marketTokenBalance", balance);
            _amount(key, "estimatedAvailableLiquidity", liquidity);
        }
        _amount(key, "quarantinedAssets", vault.quarantinedAssets(market));
        _amount(key, "cap", config.cap);
        VM.serializeBool(key, "enabled", config.enabled);
        VM.serializeUint(key, "removableAt", config.removableAt);
        PendingUint192 memory pending = vault.pendingCap(market);
        _amount(key, "pendingCap", pending.value);
        return VM.serializeUint(key, "pendingCapAt", pending.validAt);
    }

    function _shareholderJson(address vault, address account) private returns (string memory) {
        string memory key = "vault-shareholder";
        VM.serializeAddress(key, "account", account);
        _amount(key, "shares", IERC4626(vault).balanceOf(account));
        _amount(key, "maxWithdraw", IERC4626(vault).maxWithdraw(account));
        return _amount(key, "maxRedeem", IERC4626(vault).maxRedeem(account));
    }

    function _borrowerPositionJson(address market, address borrower) private returns (string memory) {
        Position memory position = IMarket(market).position(borrower);
        string memory key = "vault-borrower";
        VM.serializeAddress(key, "market", market);
        VM.serializeAddress(key, "borrower", borrower);
        _amount(key, "borrowShares", position.borrowShares);
        _amount(key, "collateralAssets", position.collateralAssets);
        return _amount(key, "expectedBorrowAssets", market.expectedBorrowAssets(borrower));
    }

    function _amount(string memory key, string memory field, uint256 value) private returns (string memory) {
        return VM.serializeString(key, field, VM.toString(value));
    }

    function _validateIdentity(VaultOffboardingManifest memory manifest) private view {
        bytes memory id = bytes(manifest.activationId);
        require(id.length != 0 && id.length <= 96, "ERP manifest: invalid activation ID");
        for (uint256 i; i < id.length; ++i) {
            require(
                (id[i] >= 0x61 && id[i] <= 0x7a) || (id[i] >= 0x41 && id[i] <= 0x5a) || (id[i] >= 0x30 && id[i] <= 0x39)
                    || id[i] == 0x2d || id[i] == 0x5f,
                "ERP manifest: invalid activation ID"
            );
        }
        require(
            manifest.t0 != 0 && manifest.step != 0 && manifest.sourceBlock != 0 && manifest.deploymentId != 0,
            "ERP manifest: missing metadata"
        );
    }

    function validateInventory(VaultOffboardingManifest memory manifest) internal view {
        require(manifest.vault.code.length != 0, "ERP manifest: missing Vault");
        _unique(manifest.markets);
        _unique(manifest.shareholders);
        _unique(manifest.allocatorsToRevoke);
        _unique(manifest.quarantinedMarkets);
        for (uint256 i; i < manifest.quarantinedMarkets.length; ++i) {
            require(
                ERPVaultQueue.contains(manifest.markets, manifest.quarantinedMarkets[i]),
                "ERP manifest: quarantine market omitted"
            );
        }
    }

    function _validateTokens(VaultOffboardingManifest memory manifest) private view {
        bool assetListed;
        for (uint256 i; i < manifest.tokens.length; ++i) {
            address token = manifest.tokens[i].token;
            require(
                token.code.length != 0 && token != manifest.vault && manifest.tokens[i].recipient != manifest.vault,
                "ERP manifest: invalid token treatment"
            );
            assetListed = assetListed || token == IERC4626(manifest.vault).asset();
            for (uint256 j; j < i; ++j) {
                require(token != manifest.tokens[j].token, "ERP manifest: duplicate token");
            }
        }
        require(assetListed, "ERP manifest: underlying token omitted");
    }

    function _unique(address[] memory values) private pure {
        for (uint256 i; i < values.length; ++i) {
            require(values[i] != address(0), "ERP manifest: zero address");
            for (uint256 j; j < i; ++j) {
                require(values[i] != values[j], "ERP manifest: duplicate address");
            }
        }
    }
}
