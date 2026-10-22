// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Balance, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {ERPMarketOffboardingSimulation} from "../../scripts/ERPMarketOffboardingSimulation.s.sol";
import {
    MintBorrowerList,
    MintBorrowerSimulationResult,
    MintMarketOffboardingIO
} from "../libraries/MintMarketOffboardingIO.sol";
import {
    MintMarketOffboardingInput,
    MintMarketOffboardingManifest,
    MintMarketOffboardingPhase,
    MintMarketOffboardingReport,
    MintMarketOffboardingSimulationTotals
} from "../IMintMarketOffboarding.sol";

/// @notice Loads one approved activation and prepares the requested ERP-OFFBOARD-01 phase.
contract MintMarketOffboardingScript is ERPMarketOffboardingSimulation {
    address internal constant SIMULATION_LIQUIDATOR =
        address(uint160(uint256(keccak256("ERP_OFFBOARD_01_LIQUIDATOR"))));

    struct BatchBSimulation {
        MintBorrowerSimulationResult[] borrowerResults;
        uint256 borrowerCount;
        MintMarketOffboardingSimulationTotals[] marketTotals;
        bytes32 operationId;
    }

    // Entrypoint and artifact lifecycle.

    function run(uint256 phaseId, string calldata manifestPath) external {
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase(phaseId);
        MintMarketOffboardingManifest memory manifest = MintMarketOffboardingIO.loadActivationManifest(manifestPath);
        MintMarketOffboardingInput memory input = MintMarketOffboardingIO.loadCurrentChainInput(manifest.deploymentId);

        if (phase == MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            MintBorrowerList memory borrowerList = _writeBorrowerList(manifestPath, manifest);
            _removeBatchBArtifacts(
                MintMarketOffboarding.artifactDirectory(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest)
            );
            BatchBSimulation memory simulation = _assertBatchBSimulation(manifest, input, borrowerList);
            _runPhase(phase, manifest, input);
            MintMarketOffboardingIO.writeSimulationReport(
                manifest,
                simulation.borrowerResults,
                simulation.borrowerCount,
                simulation.marketTotals,
                simulation.operationId
            );
        } else {
            _runPhase(phase, manifest, input);
        }
        MintMarketOffboardingIO.writeManifestInput(manifestPath, phase, manifest);
    }

    function _writeBorrowerList(string memory manifestPath, MintMarketOffboardingManifest memory manifest)
        internal
        virtual
        returns (MintBorrowerList memory)
    {
        return MintMarketOffboardingIO.writeBorrowerList(manifestPath, manifest);
    }

    // Timelock simulation.

    function _assertBatchBSimulation(
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input,
        MintBorrowerList memory borrowerList
    ) internal returns (BatchBSimulation memory simulation) {
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");

        MintMarketOffboardingReport memory report = MintMarketOffboarding._prepareRateAndLtvReduction(manifest, input);
        (MintBorrowerSimulationResult[] memory results, uint256 resultCount) =
            _buildBorrowerResults(manifest, borrowerList);
        (bytes memory scheduleData, bytes memory executeData, bytes32 operationId) = ERPOutputWriter.timelockCalldata(
            input.contracts.timelock, report.timelockBatch, report.timelockDelay, report.predecessor
        );

        uint256 snapshotId = vm.snapshotState();
        _prepareSimulationOperation(input.contracts.timelock, manifest.timelockSafe, operationId, scheduleData);

        for (uint256 i; i < resultCount; ++i) {
            results[i].liquidatableBefore = _isLiquidatable(results[i].market, results[i].borrower);
        }

        _callFrom(manifest.timelockSafe, input.contracts.timelock, executeData);
        MintMarketOffboardingSimulationTotals[] memory marketTotals =
            _simulateLiquidations(results, resultCount, manifest, input.contracts.dusd);

        simulation.borrowerResults = results;
        simulation.borrowerCount = resultCount;
        simulation.marketTotals = marketTotals;
        simulation.operationId = operationId;

        require(vm.revertToState(snapshotId), "Simulation: failed to restore fork state");
    }

    function _runPhase(
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input
    ) internal returns (MintMarketOffboardingInput memory) {
        vm.startBroadcast();
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");
        input = MintMarketOffboarding.runPhase(phase, manifest, input);
        vm.stopBroadcast();
        return input;
    }

    // Borrower discovery and classification.

    function _buildBorrowerResults(MintMarketOffboardingManifest memory manifest, MintBorrowerList memory borrowerList)
        internal
        view
        returns (MintBorrowerSimulationResult[] memory results, uint256 resultCount)
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
        results = new MintBorrowerSimulationResult[](positions.length);
        resultCount = count;
        for (uint256 i; i < resultCount; ++i) {
            results[i].market = positions[i].market;
            results[i].borrower = positions[i].borrower;
            results[i].borrowShares = positions[i].borrowShares;
            results[i].collateralAssets = positions[i].collateralAssets;
        }
    }

    // Isolated liquidation simulation.

    function _simulateLiquidations(
        MintBorrowerSimulationResult[] memory results,
        uint256 resultCount,
        MintMarketOffboardingManifest memory manifest,
        address dusdAddress
    ) internal returns (MintMarketOffboardingSimulationTotals[] memory marketTotals) {
        marketTotals = new MintMarketOffboardingSimulationTotals[](manifest.markets.length);
        IDUSD dusd = IDUSD(dusdAddress);

        for (uint256 i; i < manifest.markets.length; ++i) {
            address marketAddress = manifest.markets[i].market;
            IMarket market = IMarket(marketAddress);
            Balance memory borrowed = market.totalBorrowed();
            if (borrowed.assets == 0 && borrowed.shares == 0) continue;

            (uint256 minted,) = dusd.minterConfig(marketAddress);
            uint256 initialBadDebtAssets = AltoMintMarket(marketAddress).badDebtAssets();
            marketTotals[i].badDebtAssets = initialBadDebtAssets;

            for (uint256 j; j < resultCount; ++j) {
                if (results[j].market == marketAddress) _attemptLiquidation(results[j], marketTotals[i]);
            }

            MintMarketOffboardingSimulationTotals memory totals = marketTotals[i];
            uint256 simulatedBadDebtAssets = totals.badDebtAssets - initialBadDebtAssets;
            uint256 resolvedDebt = totals.liquidationFundingAssets + simulatedBadDebtAssets;
            totals.remainingBorrowedAssets = borrowed.assets > resolvedDebt ? borrowed.assets - resolvedDebt : 0;
            require(totals.liquidationFundingAssets <= minted, "Simulation: liquidation funding exceeds DUSD minted");
            totals.remainingDusdMintedAssets = minted - totals.liquidationFundingAssets;
            marketTotals[i] = totals;
            MintMarketOffboarding._validateSimulationLimits(totals, manifest.markets[i]);
        }
    }

    function _attemptLiquidation(
        MintBorrowerSimulationResult memory result,
        MintMarketOffboardingSimulationTotals memory totals
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
        totals.liquidationFundingAssets += liquidation.repaidBorrowAssets;
        totals.badDebtAssets += liquidation.badDebtAssets;
        totals.seizedCollateralAssets += liquidation.seizedCollateralAssets;
        vm.revertToState(snapshotId);
    }

    function _simulationLiquidator() internal pure override returns (address) {
        return SIMULATION_LIQUIDATOR;
    }
}
