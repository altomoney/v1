// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Balance, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {ERPMarketOffboardingSimulation} from "../../scripts/ERPMarketOffboardingSimulation.s.sol";
import {
    BorrowerList,
    BorrowerSimulationResult,
    BorrowMarketOffboardingIO
} from "../libraries/BorrowMarketOffboardingIO.sol";
import {
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingManifest,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingReport,
    BorrowMarketOffboardingSimulationTotals
} from "../IBorrowMarketOffboarding.sol";

/// @notice Loads one approved activation manifest and prepares the requested ERP-OFFBOARD-02 phase.
/// @dev Pass both values at runtime; no incident-specific library or script edits are required.
contract BorrowMarketOffboardingScript is ERPMarketOffboardingSimulation {
    using AssetShareConversionMath for uint256;

    address internal constant SIMULATION_LIQUIDATOR =
        address(uint160(uint256(keccak256("ERP_OFFBOARD_02_LIQUIDATOR"))));

    struct BatchBSimulation {
        BorrowerSimulationResult[] borrowerResults;
        uint256 borrowerCount;
        BorrowMarketOffboardingSimulationTotals[] marketTotals;
        uint256[] vaultLosses;
        bytes32 operationId;
    }

    function run(uint256 phaseId, string calldata manifestPath) external {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase(phaseId);
        BorrowMarketOffboardingManifest memory manifest = BorrowMarketOffboardingIO.loadActivationManifest(manifestPath);
        BorrowMarketOffboardingInput memory input =
            BorrowMarketOffboardingIO.loadCurrentChainInput(manifest.deploymentId);

        if (phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            BorrowerList memory borrowerList = _writeBorrowerList(manifestPath, manifest);
            _removeBatchBArtifacts(
                BorrowMarketOffboarding.artifactDirectory(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest)
            );
            BatchBSimulation memory simulation = _assertBatchBSimulation(manifest, input, borrowerList);
            _runPhase(phase, manifest, input);
            BorrowMarketOffboardingIO.writeSimulationReport(
                manifest,
                simulation.borrowerResults,
                simulation.borrowerCount,
                simulation.marketTotals,
                simulation.vaultLosses,
                simulation.operationId
            );
        } else {
            _runPhase(phase, manifest, input);
        }
        BorrowMarketOffboardingIO.writeManifestInput(manifestPath, phase, manifest);
    }

    /// @notice Writes the fetched Batch B borrower list to the standard artifact directory.
    function _writeBorrowerList(string memory manifestPath, BorrowMarketOffboardingManifest memory manifest)
        internal
        virtual
        returns (BorrowerList memory)
    {
        return BorrowMarketOffboardingIO.writeBorrowerList(manifestPath, manifest);
    }

    /// @notice Asserts the exact Batch B calls are safe, then restores the fork state.
    function _assertBatchBSimulation(
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input,
        BorrowerList memory borrowerList
    ) internal returns (BatchBSimulation memory simulation) {
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");

        BorrowMarketOffboardingReport memory report =
            BorrowMarketOffboarding.prepareRateAndLtvReduction(manifest, input);
        (BorrowerSimulationResult[] memory results, uint256 resultCount) = _buildBorrowerResults(manifest, borrowerList);
        (bytes memory scheduleData, bytes memory executeData, bytes32 operationId) = ERPOutputWriter.timelockCalldata(
            input.contracts.timelock, report.timelockBatch, report.timelockDelay, report.predecessor
        );

        uint256 snapshotId = vm.snapshotState();
        _prepareSimulationOperation(input.contracts.timelock, manifest.timelockSafe, operationId, scheduleData);

        for (uint256 i; i < resultCount; ++i) {
            results[i].liquidatableBefore = _isLiquidatable(results[i].market, results[i].borrower);
        }

        _callFrom(manifest.timelockSafe, input.contracts.timelock, executeData);
        (BorrowMarketOffboardingSimulationTotals[] memory marketTotals, uint256[] memory vaultLosses) =
            _simulateLiquidations(results, resultCount, manifest);

        simulation.borrowerResults = results;
        simulation.borrowerCount = resultCount;
        simulation.marketTotals = marketTotals;
        simulation.vaultLosses = vaultLosses;
        simulation.operationId = operationId;

        require(vm.revertToState(snapshotId), "Simulation: failed to restore fork state");
    }

    function _runPhase(
        BorrowMarketOffboardingPhase phase,
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input
    ) internal returns (BorrowMarketOffboardingInput memory) {
        vm.startBroadcast();
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");
        input = BorrowMarketOffboarding.runPhase(phase, manifest, input);
        vm.stopBroadcast();

        return input;
    }

    function _buildBorrowerResults(BorrowMarketOffboardingManifest memory manifest, BorrowerList memory borrowerList)
        internal
        view
        returns (BorrowerSimulationResult[] memory results, uint256 resultCount)
    {
        address[] memory markets = new address[](manifest.markets.length);
        for (uint256 i; i < markets.length; ++i) {
            markets[i] = manifest.markets[i].market;
        }
        BorrowerMarket[] memory borrowerMarkets = new BorrowerMarket[](borrowerList.markets.length);
        for (uint256 i; i < borrowerMarkets.length; ++i) {
            borrowerMarkets[i] =
                BorrowerMarket({borrowers: borrowerList.markets[i].borrowers, market: borrowerList.markets[i].market});
        }
        (BorrowerPosition[] memory positions, uint256 count) = _collectBorrowerPositions(markets, borrowerMarkets);
        results = new BorrowerSimulationResult[](positions.length);
        resultCount = count;
        for (uint256 i; i < resultCount; ++i) {
            results[i].market = positions[i].market;
            results[i].borrower = positions[i].borrower;
            results[i].borrowShares = positions[i].borrowShares;
            results[i].collateralAssets = positions[i].collateralAssets;
        }
    }

    function _simulateLiquidations(
        BorrowerSimulationResult[] memory results,
        uint256 resultCount,
        BorrowMarketOffboardingManifest memory manifest
    ) internal returns (BorrowMarketOffboardingSimulationTotals[] memory marketTotals, uint256[] memory vaultLosses) {
        marketTotals = new BorrowMarketOffboardingSimulationTotals[](manifest.markets.length);
        vaultLosses = new uint256[](manifest.vaults.length);
        Balance[] memory marketSupplyBefore = new Balance[](manifest.markets.length);
        uint256[] memory marketSupplyAssetsAfter = new uint256[](manifest.markets.length);

        for (uint256 i; i < manifest.markets.length; ++i) {
            IMarket market = IMarket(manifest.markets[i].market);
            market.accrueInterest();
            Balance memory supplyBefore = market.totalSupply();
            marketSupplyBefore[i] = supplyBefore;
            uint256 protocolAssetsBefore =
                _supplyAssets(market, market.feeRecipient(), supplyBefore.assets, supplyBefore.shares);

            for (uint256 j; j < resultCount; ++j) {
                if (results[j].market == address(market)) _attemptLiquidation(results[j], marketTotals[i]);
            }

            uint256 supplyAssetsAfter = supplyBefore.assets > marketTotals[i].supplierLossAssets
                ? supplyBefore.assets - marketTotals[i].supplierLossAssets
                : 0;
            marketSupplyAssetsAfter[i] = supplyAssetsAfter;
            uint256 protocolAssetsAfter =
                _supplyAssets(market, market.feeRecipient(), supplyAssetsAfter, supplyBefore.shares);
            marketTotals[i].protocolLossAssets =
                protocolAssetsBefore > protocolAssetsAfter ? protocolAssetsBefore - protocolAssetsAfter : 0;

            BorrowMarketOffboarding.validateSimulationLimits(marketTotals[i], manifest.markets[i]);
        }

        for (uint256 i; i < manifest.vaults.length; ++i) {
            address vault = manifest.vaults[i].vault;
            for (uint256 j; j < manifest.markets.length; ++j) {
                IMarket market = IMarket(manifest.markets[j].market);
                Balance memory supplyBefore = marketSupplyBefore[j];
                uint256 vaultAssetsBefore = _supplyAssets(market, vault, supplyBefore.assets, supplyBefore.shares);
                uint256 vaultAssetsAfter = _supplyAssets(market, vault, marketSupplyAssetsAfter[j], supplyBefore.shares);
                vaultLosses[i] += vaultAssetsBefore > vaultAssetsAfter ? vaultAssetsBefore - vaultAssetsAfter : 0;
            }
            require(vaultLosses[i] <= manifest.vaults[i].maxVaultLossAssets, "Simulation: Vault loss limit exceeded");
        }
    }

    function _attemptLiquidation(
        BorrowerSimulationResult memory result,
        BorrowMarketOffboardingSimulationTotals memory totals
    ) internal {
        (bool liquidatable, LiquidationOutcome memory liquidation, uint256 snapshotId) =
            _beginLiquidationAttempt(result.market, result.borrower);
        if (!liquidatable) {
            result.liquidatableAfter = false;
            return;
        }

        result.liquidatableAfter = true;
        result.repaidBorrowAssets = liquidation.repaidBorrowAssets;
        result.seizedCollateralAssets = liquidation.seizedCollateralAssets;
        result.badDebtAssets = liquidation.badDebtAssets;
        result.supplierLossAssets = liquidation.badDebtAssets;
        totals.liquidationFundingAssets += liquidation.repaidBorrowAssets;
        totals.badDebtAssets += liquidation.badDebtAssets;
        totals.supplierLossAssets += liquidation.badDebtAssets;
        vm.revertToState(snapshotId);
    }

    function _supplyAssets(IMarket market, address account, uint256 totalSupplyAssets, uint256 totalSupplyShares)
        internal
        view
        returns (uint256)
    {
        return uint256(market.position(account).supplyShares).convertToAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function _simulationLiquidator() internal pure override returns (address) {
        return SIMULATION_LIQUIDATOR;
    }
}
