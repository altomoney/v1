// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
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

    string internal constant MAINNET_DEPLOYMENT_OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string internal constant BORROWER_FETCHER_SCRIPT = "ERP/ERP-OFFBOARD-01/scripts/fetch-borrowers.ts";

    function writeBorrowerList(string memory manifestPath, MintMarketOffboardingManifest memory manifest)
        internal
        returns (MintBorrowerList memory)
    {
        string[] memory command = new string[](4);
        command[0] = "node";
        command[1] = BORROWER_FETCHER_SCRIPT;
        command[2] = manifestPath;
        command[3] = borrowerListPath(manifest);
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
        manifest.activationId = VM.parseJsonString(json, ".activationId");
        uint256 severity = VM.parseJsonUint(json, ".severity");
        require(severity <= uint256(MintMarketOffboardingSeverity.CRITICAL), "ERP manifest: invalid severity");
        manifest.severity = MintMarketOffboardingSeverity(severity);
        uint256 schedulePhase = VM.parseJsonUint(json, ".schedulePhase");
        require(
            schedulePhase <= uint256(MintMarketOffboardingSchedulePhase.TERMINAL),
            "ERP manifest: invalid schedule phase"
        );
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase(schedulePhase);
        manifest.t0 = VM.parseJsonUint(json, ".t0");
        manifest.step = VM.parseJsonUint(json, ".step");
        manifest.lastExecutedStep = VM.parseJsonUint(json, ".lastExecutedStep");
        manifest.lastStepExecutedAt = VM.parseJsonUint(json, ".lastStepExecutedAt");
        manifest.lastOperationId = VM.parseJsonBytes32(json, ".lastOperationId");
        manifest.sourceBlock = VM.parseJsonUint(json, ".sourceBlock");
        manifest.deploymentId = VM.parseJsonUint(json, ".deploymentId");
        manifest.freezerSafe = VM.parseJsonAddress(json, ".freezerSafe");
        manifest.timelockSafe = VM.parseJsonAddress(json, ".timelockSafe");
        manifest.fixedRateIrmVersion = VM.parseJsonUint(json, ".fixedRateIrmVersion");
        manifest.markets = abi.decode(VM.parseJson(json, ".markets"), (MintMarketOffboardingMarket[]));
        _validateManifest(manifest);
    }

    function loadCurrentChainInput(uint256 deploymentId)
        internal
        view
        returns (MintMarketOffboardingInput memory input)
    {
        string memory json = VM.readFile(string.concat(_deploymentFolder(deploymentId), "/addresses.json"));
        input.contracts.altoAdapter = VM.parseJsonAddress(json, ".contracts.altoAdapter");
        input.contracts.dusd = VM.parseJsonAddress(json, ".contracts.dusd");
        input.contracts.liquidationPeriphery = VM.parseJsonAddress(json, ".contracts.liquidationPeriphery");
        input.contracts.marketRegistry = VM.parseJsonAddress(json, ".contracts.marketRegistry");
        input.contracts.ownerFixedRateIrmFactory = _tryParseAddress(json, ".contracts.ownerFixedRateIrmFactory");
        input.contracts.timelock = VM.parseJsonAddress(json, ".contracts.timelock");
    }

    function writeManifestInput(
        string memory manifestPath,
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest
    ) internal {
        string memory path = _artifactPath(phase, manifest, "inputs.json");
        VM.writeFile(path, VM.readFile(manifestPath));
        console2.log("ERP inputs written:", path);
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
            '{"passed":true,"methodology":"isolated-current-oracle","chainId":"',
            VM.toString(block.chainid),
            '","sourceBlock":"',
            VM.toString(manifest.sourceBlock),
            '","operationId":"',
            VM.toString(operationId),
            '","markets":[',
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
        return string.concat(
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
            VM.toString(result.badDebtAssets),
            '"}'
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

    function _validateManifest(MintMarketOffboardingManifest memory manifest) private pure {
        require(bytes(manifest.activationId).length != 0, "ERP manifest: empty activation ID");
        require(manifest.t0 != 0, "ERP manifest: zero T0");
        require(manifest.step != 0, "ERP manifest: zero step");
        require(manifest.lastExecutedStep < manifest.step, "ERP manifest: invalid last executed step");
        require(manifest.sourceBlock != 0, "ERP manifest: zero source block");
        require(manifest.deploymentId != 0, "ERP manifest: zero deployment ID");
        require(manifest.freezerSafe != address(0), "ERP manifest: zero freezer Safe");
        require(manifest.timelockSafe != address(0), "ERP manifest: zero Timelock Safe");
        require(manifest.fixedRateIrmVersion != 0, "ERP manifest: zero IRM version");
        require(manifest.markets.length != 0, "ERP manifest: no markets");

        for (uint256 i; i < manifest.markets.length; ++i) {
            MintMarketOffboardingMarket memory configuredMarket = manifest.markets[i];
            require(configuredMarket.market != address(0), "ERP manifest: zero market");
            require(configuredMarket.leverage != address(0), "ERP manifest: zero leverage");
            for (uint256 j; j < i; ++j) {
                require(configuredMarket.market != manifest.markets[j].market, "ERP manifest: duplicate market");
            }
        }
    }

    function _tryParseAddress(string memory json, string memory path) private pure returns (address) {
        try VM.parseJsonAddress(json, path) returns (address parsed) {
            return parsed;
        } catch {
            return address(0);
        }
    }

    function _artifactPath(
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest,
        string memory fileName
    ) private pure returns (string memory) {
        return string.concat(MintMarketOffboarding.artifactDirectory(phase, manifest), "/", fileName);
    }

    function _deploymentFolder(uint256 deploymentId) private view returns (string memory) {
        return string.concat(
            MAINNET_DEPLOYMENT_OUTPUT_DIR,
            "/ethereum-mainnet-",
            VM.toString(block.chainid),
            "-",
            VM.toString(deploymentId)
        );
    }
}
