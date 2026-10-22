// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Shared manifest, path, borrower-fetch and JSON helpers for market offboarding ERPs.
library ERPMarketOffboardingIO {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant MAINNET_DEPLOYMENT_OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    struct ManifestMetadata {
        string activationId;
        uint256 severity;
        uint256 schedulePhase;
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
    }

    struct BorrowerResult {
        address market;
        address borrower;
        uint256 borrowShares;
        uint256 collateralAssets;
        bool liquidatableBefore;
        bool liquidatableAfter;
        uint256 repaidBorrowAssets;
        uint256 seizedCollateralAssets;
        uint256 badDebtAssets;
        uint256 supplierLossAssets;
    }

    function parseManifestMetadata(string memory json) internal pure returns (ManifestMetadata memory metadata) {
        return parseManifestMetadata(json, true);
    }

    /// @dev Preserve each ERP's original JSON field parsing order.
    function parseManifestMetadata(string memory json, bool stepBeforeHistory)
        internal
        pure
        returns (ManifestMetadata memory metadata)
    {
        metadata.activationId = VM.parseJsonString(json, ".activationId");
        metadata.severity = VM.parseJsonUint(json, ".severity");
        require(metadata.severity <= 2, "ERP manifest: invalid severity");
        metadata.schedulePhase = VM.parseJsonUint(json, ".schedulePhase");
        require(metadata.schedulePhase <= 1, "ERP manifest: invalid schedule phase");
        metadata.t0 = VM.parseJsonUint(json, ".t0");
        if (stepBeforeHistory) metadata.step = VM.parseJsonUint(json, ".step");
        metadata.lastExecutedStep = VM.parseJsonUint(json, ".lastExecutedStep");
        metadata.lastStepExecutedAt = VM.parseJsonUint(json, ".lastStepExecutedAt");
        metadata.lastOperationId = VM.parseJsonBytes32(json, ".lastOperationId");
        if (!stepBeforeHistory) metadata.step = VM.parseJsonUint(json, ".step");
        metadata.sourceBlock = VM.parseJsonUint(json, ".sourceBlock");
        metadata.deploymentId = VM.parseJsonUint(json, ".deploymentId");
        metadata.freezerSafe = VM.parseJsonAddress(json, ".freezerSafe");
        metadata.timelockSafe = VM.parseJsonAddress(json, ".timelockSafe");
        metadata.fixedRateIrmVersion = VM.parseJsonUint(json, ".fixedRateIrmVersion");
    }

    function validateManifestMetadata(ManifestMetadata memory metadata) internal pure {
        validateManifestMetadata(metadata, true);
    }

    function validateManifestMetadata(ManifestMetadata memory metadata, bool t0BeforeStep) internal pure {
        require(bytes(metadata.activationId).length != 0, "ERP manifest: empty activation ID");
        if (t0BeforeStep) {
            require(metadata.t0 != 0, "ERP manifest: zero T0");
            require(metadata.step != 0, "ERP manifest: zero step");
        } else {
            require(metadata.step != 0, "ERP manifest: zero step");
            require(metadata.t0 != 0, "ERP manifest: zero T0");
        }
        require(metadata.lastExecutedStep < metadata.step, "ERP manifest: invalid last executed step");
        require(metadata.sourceBlock != 0, "ERP manifest: zero source block");
        require(metadata.deploymentId != 0, "ERP manifest: zero deployment ID");
        require(metadata.freezerSafe != address(0), "ERP manifest: zero freezer Safe");
        require(metadata.timelockSafe != address(0), "ERP manifest: zero Timelock Safe");
        require(metadata.fixedRateIrmVersion != 0, "ERP manifest: zero IRM version");
    }

    function validateMarkets(address[] memory markets, address[] memory leverages) internal pure {
        require(markets.length != 0, "ERP manifest: no markets");
        assert(markets.length == leverages.length);
        for (uint256 i; i < markets.length; ++i) {
            require(markets[i] != address(0), "ERP manifest: zero market");
            require(leverages[i] != address(0), "ERP manifest: zero leverage");
            for (uint256 j; j < i; ++j) {
                require(markets[i] != markets[j], "ERP manifest: duplicate market");
            }
        }
    }

    function borrowerFetcherCommand(string memory manifestPath, string memory outputPath)
        internal
        pure
        returns (string[] memory command)
    {
        command = new string[](4);
        command[0] = "node";
        command[1] = "ERP/scripts/fetch-borrowers.ts";
        command[2] = manifestPath;
        command[3] = outputPath;
    }

    function deploymentFolder(uint256 chainId, uint256 deploymentId) internal pure returns (string memory) {
        return string.concat(
            MAINNET_DEPLOYMENT_OUTPUT_DIR, "/ethereum-mainnet-", VM.toString(chainId), "-", VM.toString(deploymentId)
        );
    }

    function writeManifestInput(string memory manifestPath, string memory path) internal {
        VM.writeFile(path, VM.readFile(manifestPath));
        console2.log("ERP inputs written:", path);
    }

    function artifactPath(string memory directory, string memory fileName) internal pure returns (string memory) {
        return string.concat(directory, "/", fileName);
    }

    function tryParseAddress(string memory json, string memory path) internal pure returns (address) {
        try VM.parseJsonAddress(json, path) returns (address parsed) {
            return parsed;
        } catch {
            return address(0);
        }
    }

    function borrowerResultJson(BorrowerResult memory result, bool includeSupplierLoss)
        internal
        pure
        returns (string memory json)
    {
        json = string.concat(
            '{"market":"',
            VM.toString(result.market),
            '","borrower":"',
            VM.toString(result.borrower),
            '","borrowShares":"',
            VM.toString(result.borrowShares),
            '","collateralAssets":"',
            VM.toString(result.collateralAssets),
            '","liquidatableBefore":',
            VM.toString(result.liquidatableBefore),
            ',"liquidatableAfter":',
            VM.toString(result.liquidatableAfter),
            ',"newlyLiquidatable":',
            VM.toString(!result.liquidatableBefore && result.liquidatableAfter),
            ',"repaidBorrowAssets":"',
            VM.toString(result.repaidBorrowAssets),
            '","seizedCollateralAssets":"',
            VM.toString(result.seizedCollateralAssets),
            '","badDebtAssets":"',
            VM.toString(result.badDebtAssets)
        );
        if (includeSupplierLoss) {
            json = string.concat(json, '","supplierLossAssets":"', VM.toString(result.supplierLossAssets));
        }
        return string.concat(json, '"}');
    }

    function simulationReportPrefix(uint256 sourceBlock, bytes32 operationId) internal view returns (string memory) {
        return string.concat(
            '{"passed":true,"methodology":"isolated-current-oracle","chainId":"',
            VM.toString(block.chainid),
            '","sourceBlock":"',
            VM.toString(sourceBlock),
            '","operationId":"',
            VM.toString(operationId),
            '"'
        );
    }
}
