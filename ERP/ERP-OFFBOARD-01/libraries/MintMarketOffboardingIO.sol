// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
import {ERPMarketOffboardingIO} from "../../libraries/ERPMarketOffboardingIO.sol";
import {
    MintMarketOffboardingBorrowerMarket,
    MintMarketOffboardingInput,
    MintMarketOffboardingManifest,
    MintMarketOffboardingMarket,
    MintMarketOffboardingPhase,
    MintMarketOffboardingSchedulePhase,
    MintMarketOffboardingSimulationTotals,
    MintMarketOffboardingSeverity
} from "../IMintMarketOffboarding.sol";

struct MintBorrowerList {
    MintMarketOffboardingBorrowerMarket[] markets;
}

struct MintBorrowerSimulationResult {
    address market;
    address borrower;
    uint256 borrowShares;
    uint256 collateralAssets;
    bool liquidatableBefore;
    bool liquidatableAfter;
    uint256 repaidBorrowAssets;
    uint256 seizedCollateralAssets;
    uint256 badDebtAssets;
}

/// @notice Reads ERP-OFFBOARD-01 inputs and writes reproducible operational evidence.
library MintMarketOffboardingIO {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function writeBorrowerList(string memory manifestPath, MintMarketOffboardingManifest memory manifest)
        internal
        returns (MintBorrowerList memory)
    {
        string[] memory command =
            ERPMarketOffboardingIO.borrowerFetcherCommand(manifestPath, borrowerListPath(manifest));
        return parseBorrowerList(string(VM.ffi(command)));
    }

    function parseBorrowerList(string memory json) internal pure returns (MintBorrowerList memory borrowerList) {
        borrowerList.markets = abi.decode(VM.parseJson(json, ".markets"), (MintMarketOffboardingBorrowerMarket[]));
    }

    function loadActivationManifest(string memory path)
        internal
        view
        returns (MintMarketOffboardingManifest memory manifest)
    {
        string memory json = VM.readFile(path);
        ERPMarketOffboardingIO.ManifestMetadata memory metadata = ERPMarketOffboardingIO.parseManifestMetadata(json);
        manifest.activationId = metadata.activationId;
        manifest.severity = MintMarketOffboardingSeverity(metadata.severity);
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase(metadata.schedulePhase);
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
        manifest.markets = abi.decode(VM.parseJson(json, ".markets"), (MintMarketOffboardingMarket[]));
        _validateManifest(manifest, metadata);
    }

    function loadCurrentChainInput(uint256 deploymentId)
        internal
        view
        returns (MintMarketOffboardingInput memory input)
    {
        string memory json = VM.readFile(
            string.concat(ERPMarketOffboardingIO.deploymentFolder(block.chainid, deploymentId), "/addresses.json")
        );
        input.contracts.altoAdapter = VM.parseJsonAddress(json, ".contracts.altoAdapter");
        input.contracts.dusd = VM.parseJsonAddress(json, ".contracts.dusd");
        input.contracts.liquidationPeriphery = VM.parseJsonAddress(json, ".contracts.liquidationPeriphery");
        input.contracts.marketRegistry = VM.parseJsonAddress(json, ".contracts.marketRegistry");
        input.contracts.ownerFixedRateIrmFactory =
            ERPMarketOffboardingIO.tryParseAddress(json, ".contracts.ownerFixedRateIrmFactory");
        input.contracts.timelock = VM.parseJsonAddress(json, ".contracts.timelock");
    }

    function writeManifestInput(
        string memory manifestPath,
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest
    ) internal {
        string memory path = _artifactPath(phase, manifest, "inputs.json");
        ERPMarketOffboardingIO.writeManifestInput(manifestPath, path);
    }

    function borrowerListPath(MintMarketOffboardingManifest memory manifest) internal pure returns (string memory) {
        return _artifactPath(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, "borrowers.json");
    }

    function writeSimulationReport(
        MintMarketOffboardingManifest memory manifest,
        MintBorrowerSimulationResult[] memory results,
        uint256 resultCount,
        MintMarketOffboardingSimulationTotals[] memory marketTotals,
        bytes32 operationId
    ) internal {
        string memory json = string.concat(
            ERPMarketOffboardingIO.simulationReportPrefix(manifest.sourceBlock, operationId),
            ',"markets":[',
            _marketsJson(manifest.markets, marketTotals),
            '],"borrowers":[',
            _borrowersJson(results, resultCount),
            "]}"
        );
        VM.writeFile(
            _artifactPath(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, "simulation-report.json"), json
        );
    }

    function _borrowersJson(MintBorrowerSimulationResult[] memory results, uint256 resultCount)
        private
        pure
        returns (string memory json)
    {
        for (uint256 i; i < resultCount; ++i) {
            json = string.concat(json, i == 0 ? "" : ",", _borrowerResultJson(results[i]));
        }
    }

    function _marketsJson(
        MintMarketOffboardingMarket[] memory markets,
        MintMarketOffboardingSimulationTotals[] memory marketTotals
    ) private pure returns (string memory json) {
        for (uint256 i; i < markets.length; ++i) {
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                '{"market":"',
                VM.toString(markets[i].market),
                '","limits":',
                _marketLimitsJson(markets[i]),
                ',"totals":',
                _totalsJson(marketTotals[i]),
                "}"
            );
        }
    }

    function _borrowerResultJson(MintBorrowerSimulationResult memory result) private pure returns (string memory) {
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
                supplierLossAssets: 0
            }),
            false
        );
    }

    function _marketLimitsJson(MintMarketOffboardingMarket memory market) private pure returns (string memory) {
        return string.concat(
            '{"maxLiquidationFundingAssets":"',
            VM.toString(market.maxLiquidationFundingAssets),
            '","maxBadDebtAssets":"',
            VM.toString(market.maxBadDebtAssets),
            '","maxDusdMintedAssets":"',
            VM.toString(market.maxDusdMintedAssets),
            '","maxSeizedCollateralAssets":"',
            VM.toString(market.maxSeizedCollateralAssets),
            '","maxUnbackedDusdAssets":"',
            VM.toString(market.maxUnbackedDusdAssets),
            '"}'
        );
    }

    function _totalsJson(MintMarketOffboardingSimulationTotals memory totals) private pure returns (string memory) {
        return string.concat(
            '{"liquidationFundingAssets":"',
            VM.toString(totals.liquidationFundingAssets),
            '","badDebtAssets":"',
            VM.toString(totals.badDebtAssets),
            '","seizedCollateralAssets":"',
            VM.toString(totals.seizedCollateralAssets),
            '","dusdBurnedAssets":"',
            VM.toString(totals.liquidationFundingAssets),
            '","remainingBorrowedAssets":"',
            VM.toString(totals.remainingBorrowedAssets),
            '","remainingDusdMintedAssets":"',
            VM.toString(totals.remainingDusdMintedAssets),
            '"}'
        );
    }

    function _validateManifest(
        MintMarketOffboardingManifest memory manifest,
        ERPMarketOffboardingIO.ManifestMetadata memory metadata
    ) private pure {
        ERPMarketOffboardingIO.validateManifestMetadata(metadata);
        address[] memory markets = new address[](manifest.markets.length);
        address[] memory leverages = new address[](manifest.markets.length);
        for (uint256 i; i < manifest.markets.length; ++i) {
            markets[i] = manifest.markets[i].market;
            leverages[i] = manifest.markets[i].leverage;
        }
        ERPMarketOffboardingIO.validateMarkets(markets, leverages);
    }

    function _artifactPath(
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest,
        string memory fileName
    ) private pure returns (string memory) {
        return ERPMarketOffboardingIO.artifactPath(MintMarketOffboarding.artifactDirectory(phase, manifest), fileName);
    }
}
