// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {ERPMarketOffboardingIO} from "../../libraries/ERPMarketOffboardingIO.sol";
import {
    BorrowMarketOffboardingBorrowerMarket,
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingManifest,
    BorrowMarketOffboardingMarket,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingSchedulePhase,
    BorrowMarketOffboardingSeverity,
    BorrowMarketOffboardingSimulationTotals,
    BorrowMarketOffboardingVault
} from "../IBorrowMarketOffboarding.sol";

struct BorrowerList {
    BorrowMarketOffboardingBorrowerMarket[] markets;
}

struct BorrowerSimulationResult {
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

/// @notice Reads ERP-OFFBOARD-02 inputs and writes its reproducible simulation artifacts.
library BorrowMarketOffboardingIO {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function writeBorrowerList(string memory manifestPath, BorrowMarketOffboardingManifest memory manifest)
        internal
        returns (BorrowerList memory)
    {
        string[] memory command =
            ERPMarketOffboardingIO.borrowerFetcherCommand(manifestPath, borrowerListPath(manifest));
        return parseBorrowerList(string(VM.ffi(command)));
    }

    function parseBorrowerList(string memory json) internal pure returns (BorrowerList memory borrowerList) {
        borrowerList.markets = abi.decode(VM.parseJson(json, ".markets"), (BorrowMarketOffboardingBorrowerMarket[]));
    }

    function writeSimulationReport(
        BorrowMarketOffboardingManifest memory manifest,
        BorrowerSimulationResult[] memory results,
        uint256 resultCount,
        BorrowMarketOffboardingSimulationTotals[] memory marketTotals,
        uint256[] memory vaultLosses,
        bytes32 operationId
    ) internal {
        string memory borrowerJson;
        for (uint256 i; i < resultCount; ++i) {
            borrowerJson = string.concat(borrowerJson, i == 0 ? "" : ",", _borrowerResultJson(results[i]));
        }

        string memory marketJson;
        for (uint256 i; i < manifest.markets.length; ++i) {
            marketJson = string.concat(
                marketJson,
                i == 0 ? "" : ",",
                '{"market":"',
                VM.toString(manifest.markets[i].market),
                '","totals":',
                _totalsJson(marketTotals[i]),
                "}"
            );
        }

        string memory vaultJson;
        for (uint256 i; i < manifest.vaults.length; ++i) {
            vaultJson = string.concat(
                vaultJson,
                i == 0 ? "" : ",",
                '{"vault":"',
                VM.toString(manifest.vaults[i].vault),
                '","lossAssets":"',
                VM.toString(vaultLosses[i]),
                '"}'
            );
        }

        string memory json = string.concat(
            ERPMarketOffboardingIO.simulationReportPrefix(manifest.sourceBlock, operationId),
            ',"limits":',
            _limitsJson(manifest),
            ',"markets":[',
            marketJson,
            '],"vaults":[',
            vaultJson,
            '],"borrowers":[',
            borrowerJson,
            "]}"
        );
        VM.writeFile(
            string.concat(
                BorrowMarketOffboarding.artifactDirectory(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest),
                "/simulation-report.json"
            ),
            json
        );
    }

    function writeManifestInput(
        string memory manifestPath,
        BorrowMarketOffboardingPhase phase,
        BorrowMarketOffboardingManifest memory manifest
    ) internal {
        string memory path = ERPMarketOffboardingIO.artifactPath(
            BorrowMarketOffboarding.artifactDirectory(phase, manifest), "inputs.json"
        );
        ERPMarketOffboardingIO.writeManifestInput(manifestPath, path);
    }

    function borrowerListPath(BorrowMarketOffboardingManifest memory manifest) internal pure returns (string memory) {
        return ERPMarketOffboardingIO.artifactPath(
            BorrowMarketOffboarding.artifactDirectory(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest),
            "borrowers.json"
        );
    }

    function loadActivationManifest(string memory path)
        internal
        view
        returns (BorrowMarketOffboardingManifest memory manifest)
    {
        string memory json = VM.readFile(path);
        ERPMarketOffboardingIO.ManifestMetadata memory metadata =
            ERPMarketOffboardingIO.parseManifestMetadata(json, false);
        manifest.activationId = metadata.activationId;
        manifest.severity = BorrowMarketOffboardingSeverity(metadata.severity);
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase(metadata.schedulePhase);
        manifest.t0 = metadata.t0;
        manifest.step = metadata.step;
        manifest.lastExecutedStep = metadata.lastExecutedStep;
        manifest.lastStepExecutedAt = metadata.lastStepExecutedAt;
        manifest.lastOperationId = metadata.lastOperationId;
        manifest.sourceBlock = metadata.sourceBlock;
        manifest.deploymentId = metadata.deploymentId;
        manifest.freezerSafe = metadata.freezerSafe;
        manifest.timelockSafe = metadata.timelockSafe;
        manifest.fixedRateIrmVersion = metadata.fixedRateIrmVersion;
        manifest.vaults = abi.decode(VM.parseJson(json, ".vaults"), (BorrowMarketOffboardingVault[]));
        manifest.markets = abi.decode(VM.parseJson(json, ".markets"), (BorrowMarketOffboardingMarket[]));
        _validateManifest(manifest, metadata);
    }

    function loadCurrentChainInput(uint256 deploymentId)
        internal
        view
        returns (BorrowMarketOffboardingInput memory input)
    {
        string memory json = VM.readFile(
            string.concat(ERPMarketOffboardingIO.deploymentFolder(block.chainid, deploymentId), "/addresses.json")
        );

        input.contracts.timelock = VM.parseJsonAddress(json, ".contracts.timelock");
        input.contracts.ownerFixedRateIrmFactory =
            ERPMarketOffboardingIO.tryParseAddress(json, ".contracts.ownerFixedRateIrmFactory");
        input.contracts.marketRegistry = VM.parseJsonAddress(json, ".contracts.marketRegistry");
        input.contracts.altoAdapter = VM.parseJsonAddress(json, ".contracts.altoAdapter");
        input.contracts.liquidationPeriphery = VM.parseJsonAddress(json, ".contracts.liquidationPeriphery");
    }

    function _borrowerResultJson(BorrowerSimulationResult memory result) private pure returns (string memory) {
        return ERPMarketOffboardingIO.borrowerResultJson(
            ERPMarketOffboardingIO.BorrowerResult({
                market: result.market,
                borrower: result.borrower,
                borrowShares: result.borrowShares,
                collateralAssets: result.collateralAssets,
                liquidatableBefore: result.liquidatableBefore,
                liquidatableAfter: result.liquidatableAfter,
                repaidBorrowAssets: result.repaidBorrowAssets,
                seizedCollateralAssets: result.seizedCollateralAssets,
                badDebtAssets: result.badDebtAssets,
                supplierLossAssets: result.supplierLossAssets
            }),
            true
        );
    }

    function _totalsJson(BorrowMarketOffboardingSimulationTotals memory totals) private pure returns (string memory) {
        return string.concat(
            '{"liquidationFundingAssets":"',
            VM.toString(totals.liquidationFundingAssets),
            '","badDebtAssets":"',
            VM.toString(totals.badDebtAssets),
            '","supplierLossAssets":"',
            VM.toString(totals.supplierLossAssets),
            '","protocolLossAssets":"',
            VM.toString(totals.protocolLossAssets),
            '"}'
        );
    }

    function _limitsJson(BorrowMarketOffboardingManifest memory manifest) private pure returns (string memory) {
        string memory marketJson;
        for (uint256 i; i < manifest.markets.length; ++i) {
            BorrowMarketOffboardingMarket memory market = manifest.markets[i];
            marketJson = string.concat(
                marketJson,
                i == 0 ? "" : ",",
                '{"market":"',
                VM.toString(market.market),
                '","maxLiquidationFundingAssets":"',
                VM.toString(market.maxLiquidationFundingAssets),
                '","maxBadDebtAssets":"',
                VM.toString(market.maxBadDebtAssets),
                '","maxSupplierLossAssets":"',
                VM.toString(market.maxSupplierLossAssets),
                '","maxProtocolLossAssets":"',
                VM.toString(market.maxProtocolLossAssets),
                '"}'
            );
        }

        string memory vaultJson;
        for (uint256 i; i < manifest.vaults.length; ++i) {
            BorrowMarketOffboardingVault memory vault = manifest.vaults[i];
            vaultJson = string.concat(
                vaultJson,
                i == 0 ? "" : ",",
                '{"vault":"',
                VM.toString(vault.vault),
                '","maxVaultLossAssets":"',
                VM.toString(vault.maxVaultLossAssets),
                '"}'
            );
        }

        return string.concat('{"markets":[', marketJson, '],"vaults":[', vaultJson, "]}");
    }

    function _validateManifest(
        BorrowMarketOffboardingManifest memory manifest,
        ERPMarketOffboardingIO.ManifestMetadata memory metadata
    ) private pure {
        ERPMarketOffboardingIO.validateManifestMetadata(metadata, false);
        require(manifest.markets.length != 0, "ERP manifest: no markets");
        for (uint256 i; i < manifest.vaults.length; ++i) {
            address vault = manifest.vaults[i].vault;
            require(manifest.vaults[i].allocator != address(0), "ERP manifest: zero Vault allocator");
            require(vault != address(0), "ERP manifest: zero Vault");
            for (uint256 j; j < i; ++j) {
                require(vault != manifest.vaults[j].vault, "ERP manifest: duplicate Vault");
            }
        }
        address[] memory markets = new address[](manifest.markets.length);
        address[] memory leverages = new address[](manifest.markets.length);
        for (uint256 i; i < manifest.markets.length; ++i) {
            markets[i] = manifest.markets[i].market;
            leverages[i] = manifest.markets[i].leverage;
        }
        ERPMarketOffboardingIO.validateMarkets(markets, leverages);
    }
}
