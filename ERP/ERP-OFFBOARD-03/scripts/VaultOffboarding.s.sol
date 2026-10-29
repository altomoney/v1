// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {VaultOffboarding} from "../VaultOffboarding.sol";
import {VaultOffboardingIO} from "../libraries/VaultOffboardingIO.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {ERPMarketOffboardingIO} from "../../libraries/ERPMarketOffboardingIO.sol";
import {
    VaultOffboardingAction,
    VaultOffboardingPhase,
    VaultOffboardingManifest,
    VaultOffboardingReport,
    VaultOffboardingContracts
} from "../IVaultOffboarding.sol";

/// @notice Loads one approved manifest and writes phase artifacts
contract VaultOffboardingScript is Script {
    function run(uint256 phaseId, string calldata manifestPath) external {
        VaultOffboardingPhase phase = VaultOffboardingPhase(phaseId);
        string memory json = vm.readFile(manifestPath);
        VaultOffboardingManifest memory manifest = VaultOffboardingIO.loadActivationManifest(json);
        if (phase == VaultOffboardingPhase.BATCH_B_CORRECT) {
            manifest.action = VaultOffboardingAction(vm.parseJsonUint(json, ".action"));
        }
        string memory directory = VaultOffboarding.artifactDirectory(phase, manifest);
        // Clear only this run's previous snapshot, outcome and calldata before preparation can fail.
        _removePreparationArtifacts(directory);
        VaultOffboardingIO.loadPhaseParameters(json, phase, manifest);
        VaultOffboardingIO.validateInventory(manifest);
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");
        VaultOffboardingContracts memory contracts = VaultOffboardingIO.loadCurrentChainContracts(manifest.deploymentId);
        VaultOffboardingIO.writeExposureReport(directory, manifest);
        VaultOffboardingReport memory report = VaultOffboarding.runPhase(phase, manifest, contracts);
        if (phase == VaultOffboardingPhase.BATCH_C_RECOVER) {
            VaultOffboardingIO.appendClosureOutcome(directory, manifest, report);
        }
        ERPMarketOffboardingIO.writeManifestInput(manifestPath, string.concat(directory, "/inputs.json"));
    }

    /// @notice Reports source state at any time; subgraph discovery is optional and never touches calldata outputs.
    function monitor(string calldata manifestPath, bool includeBorrowers) external {
        VaultOffboardingManifest memory manifest = VaultOffboardingIO.loadActivationManifest(vm.readFile(manifestPath));
        VaultOffboardingIO.validateInventory(manifest);
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");
        string memory directory = string.concat(
            VaultOffboarding.ERP_OUTPUT_DIR,
            "/",
            manifest.activationId,
            "/monitor/step-",
            vm.toString(manifest.step),
            "/source-block-",
            vm.toString(manifest.sourceBlock)
        );
        ERPOutputWriter.removeIfExists(string.concat(directory, "/borrowers.json"));
        VaultOffboardingIO.writeExposureReport(directory, manifest);
        if (includeBorrowers) VaultOffboardingIO.writeBorrowerReport(manifestPath, manifest, directory);
        ERPMarketOffboardingIO.writeManifestInput(manifestPath, string.concat(directory, "/inputs.json"));
    }

    function _removePreparationArtifacts(string memory directory) private {
        ERPOutputWriter.removeIfExists(string.concat(directory, "/exposure-report.json"));
        // Remove the legacy standalone outcome if this directory predates report consolidation.
        ERPOutputWriter.removeIfExists(string.concat(directory, "/closure-report.json"));
        ERPOutputWriter.removeIfExists(string.concat(directory, "/vault-curator-safe.json"));
        ERPOutputWriter.removeIfExists(string.concat(directory, "/vault-allocator.json"));
        ERPOutputWriter.removeIfExists(string.concat(directory, "/vault-governance-schedule.json"));
        ERPOutputWriter.removeIfExists(string.concat(directory, "/vault-governance-execute.json"));
    }
}
