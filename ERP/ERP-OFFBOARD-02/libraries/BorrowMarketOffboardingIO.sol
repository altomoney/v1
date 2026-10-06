// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
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

    string internal constant MAINNET_DEPLOYMENT_OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string internal constant BORROWER_FETCHER_SCRIPT = "ERP/ERP-OFFBOARD-02/scripts/fetch-borrowers.ts";

    function writeBorrowerList(string memory manifestPath, BorrowMarketOffboardingManifest memory manifest)
        internal
        returns (BorrowerList memory)
    {
        string[] memory command = new string[](4);
        command[0] = "node";
        command[1] = BORROWER_FETCHER_SCRIPT;
        command[2] = manifestPath;
        command[3] = borrowerListPath(manifest);
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
            '{"passed":true,"methodology":"isolated-current-oracle","chainId":"',
            VM.toString(block.chainid),
            '","sourceBlock":"',
            VM.toString(manifest.sourceBlock),
            '","operationId":"',
            VM.toString(operationId),
            '","limits":',
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
        string memory path = string.concat(BorrowMarketOffboarding.artifactDirectory(phase, manifest), "/inputs.json");
        VM.writeFile(path, VM.readFile(manifestPath));
        console2.log("ERP inputs written:", path);
    }

    function borrowerListPath(BorrowMarketOffboardingManifest memory manifest) internal pure returns (string memory) {
        return string.concat(
            BorrowMarketOffboarding.artifactDirectory(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest),
            "/borrowers.json"
        );
    }

    function loadActivationManifest(string memory path)
        internal
        view
        returns (BorrowMarketOffboardingManifest memory manifest)
    {
        string memory json = VM.readFile(path);
        manifest.activationId = VM.parseJsonString(json, ".activationId");
        uint256 severity = VM.parseJsonUint(json, ".severity");
        require(severity <= uint256(BorrowMarketOffboardingSeverity.CRITICAL), "ERP manifest: invalid severity");
        manifest.severity = BorrowMarketOffboardingSeverity(severity);
        uint256 schedulePhase = VM.parseJsonUint(json, ".schedulePhase");
        require(
            schedulePhase <= uint256(BorrowMarketOffboardingSchedulePhase.TERMINAL),
            "ERP manifest: invalid schedule phase"
        );
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase(schedulePhase);
        manifest.t0 = VM.parseJsonUint(json, ".t0");
        manifest.lastExecutedStep = VM.parseJsonUint(json, ".lastExecutedStep");
        manifest.lastStepExecutedAt = VM.parseJsonUint(json, ".lastStepExecutedAt");
        manifest.lastOperationId = VM.parseJsonBytes32(json, ".lastOperationId");
        manifest.step = VM.parseJsonUint(json, ".step");
        manifest.sourceBlock = VM.parseJsonUint(json, ".sourceBlock");
        manifest.deploymentId = VM.parseJsonUint(json, ".deploymentId");
        manifest.freezerSafe = VM.parseJsonAddress(json, ".freezerSafe");
        manifest.timelockSafe = VM.parseJsonAddress(json, ".timelockSafe");
        manifest.fixedRateIrmVersion = VM.parseJsonUint(json, ".fixedRateIrmVersion");
        manifest.vaults = abi.decode(VM.parseJson(json, ".vaults"), (BorrowMarketOffboardingVault[]));
        manifest.markets = abi.decode(VM.parseJson(json, ".markets"), (BorrowMarketOffboardingMarket[]));
        _validateManifest(manifest);
    }

    function loadCurrentChainInput(uint256 deploymentId)
        internal
        view
        returns (BorrowMarketOffboardingInput memory input)
    {
        string memory json = VM.readFile(string.concat(_deploymentFolder(deploymentId), "/addresses.json"));

        input.contracts.timelock = VM.parseJsonAddress(json, ".contracts.timelock");
        input.contracts.ownerFixedRateIrmFactory = _tryParseAddress(json, ".contracts.ownerFixedRateIrmFactory");
        input.contracts.marketRegistry = VM.parseJsonAddress(json, ".contracts.marketRegistry");
        input.contracts.altoAdapter = VM.parseJsonAddress(json, ".contracts.altoAdapter");
        input.contracts.liquidationPeriphery = VM.parseJsonAddress(json, ".contracts.liquidationPeriphery");
    }

    function _borrowerResultJson(BorrowerSimulationResult memory result) private pure returns (string memory) {
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
            '","supplierLossAssets":"',
            VM.toString(result.supplierLossAssets),
            '"}'
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

    function _validateManifest(BorrowMarketOffboardingManifest memory manifest) private pure {
        require(bytes(manifest.activationId).length != 0, "ERP manifest: empty activation ID");
        require(manifest.step != 0, "ERP manifest: zero step");
        require(manifest.t0 != 0, "ERP manifest: zero T0");
        require(manifest.lastExecutedStep < manifest.step, "ERP manifest: invalid last executed step");
        require(manifest.sourceBlock != 0, "ERP manifest: zero source block");
        require(manifest.deploymentId != 0, "ERP manifest: zero deployment ID");
        require(manifest.freezerSafe != address(0), "ERP manifest: zero freezer Safe");
        require(manifest.timelockSafe != address(0), "ERP manifest: zero Timelock Safe");
        require(manifest.fixedRateIrmVersion != 0, "ERP manifest: zero IRM version");
        require(manifest.markets.length != 0, "ERP manifest: no markets");

        for (uint256 i; i < manifest.vaults.length; ++i) {
            address vault = manifest.vaults[i].vault;
            require(manifest.vaults[i].allocator != address(0), "ERP manifest: zero Vault allocator");
            require(vault != address(0), "ERP manifest: zero Vault");
            for (uint256 j; j < i; ++j) {
                require(vault != manifest.vaults[j].vault, "ERP manifest: duplicate Vault");
            }
        }

        for (uint256 i; i < manifest.markets.length; ++i) {
            BorrowMarketOffboardingMarket memory configuredMarket = manifest.markets[i];
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
