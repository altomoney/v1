// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {Vm} from "forge-std/Vm.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {
    MintBorrowerList,
    MintBorrowerSimulationResult,
    MintMarketOffboardingIO
} from "../libraries/MintMarketOffboardingIO.sol";
import {
    MintMarketOffboardingBorrowerMarket,
    MintMarketOffboardingInput,
    MintMarketOffboardingManifest,
    MintMarketOffboardingPhase,
    MintMarketOffboardingReport,
    MintMarketOffboardingSimulationTotals
} from "../IMintMarketOffboarding.sol";

/// @notice Loads one approved activation and prepares the requested ERP-OFFBOARD-01 phase.
contract MintMarketOffboardingScript is Script {
    using stdStorage for StdStorage;

    StdStorage internal simulationStorage;

    address internal constant SIMULATION_LIQUIDATOR =
        address(uint160(uint256(keccak256("ERP_OFFBOARD_01_LIQUIDATOR"))));
    bytes32 internal constant LIQUIDATION_EVENT_SIG =
        keccak256("Liquidation(address,address,uint256,uint256,uint256,uint256,uint256,uint256)");

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
            _removeBatchBArtifacts(manifest);
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

    function _removeBatchBArtifacts(MintMarketOffboardingManifest memory manifest) private {
        string memory outputDirectory =
            MintMarketOffboarding.artifactDirectory(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest);
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/batch-b-irm-and-ltv-update-schedule.json"));
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/batch-b-irm-and-ltv-update-execute.json"));
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/inputs.json"));
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/simulation-report.json"));
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

    function _prepareSimulationOperation(
        address timelockAddress,
        address timelockSafe,
        bytes32 operationId,
        bytes memory scheduleData
    ) private {
        TimelockController timelock = TimelockController(payable(timelockAddress));
        if (!timelock.isOperationPending(operationId)) {
            _callFrom(timelockSafe, timelockAddress, scheduleData);
        }
        if (!timelock.isOperationReady(operationId)) vm.warp(timelock.getTimestamp(operationId));
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
        uint256 candidateCount;
        for (uint256 i; i < borrowerList.markets.length; ++i) {
            candidateCount += borrowerList.markets[i].borrowers.length;
        }
        results = new MintBorrowerSimulationResult[](candidateCount);

        for (uint256 i; i < manifest.markets.length; ++i) {
            address marketAddress = manifest.markets[i].market;
            MintMarketOffboardingBorrowerMarket memory borrowerMarket = borrowerList.markets[i];
            require(borrowerMarket.market == marketAddress, "Simulation: borrower market mismatch");

            IMarket market = IMarket(marketAddress);
            LiquidationConfiguration memory configuration =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
            require(!configuration.isEnabledPriorityLiquidation, "Simulation: priority liquidation unsupported");

            uint256 listedBorrowShares;
            for (uint256 j; j < borrowerMarket.borrowers.length; ++j) {
                address borrower = borrowerMarket.borrowers[j];
                Position memory position = market.position(borrower);
                if (position.borrowShares == 0) continue;
                listedBorrowShares += position.borrowShares;
                MintBorrowerSimulationResult memory result;
                result.market = marketAddress;
                result.borrower = borrower;
                result.borrowShares = position.borrowShares;
                result.collateralAssets = position.collateralAssets;
                results[resultCount++] = result;
            }
            require(listedBorrowShares == market.totalBorrowed().shares, "Simulation: borrower shares do not reconcile");
        }
    }

    function _isLiquidatable(address market, address borrower) internal returns (bool) {
        uint256 snapshotId = vm.snapshotState();
        (bool success,) = _callLiquidation(market, borrower);
        vm.revertToState(snapshotId);
        return success;
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
        uint256 snapshotId = vm.snapshotState();
        vm.recordLogs();
        (bool success, bytes memory returnData) = _callLiquidation(result.market, result.borrower);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        if (!success) {
            bool solvent = _isSolventPositionError(returnData);
            vm.revertToState(snapshotId);
            if (!solvent) _bubbleRevert(returnData);
            result.liquidatableAfter = false;
            return;
        }

        (uint256 seizedCollateralAssets, uint256 repaidBorrowAssets, uint256 badDebtAssets) =
            _liquidationOutcome(logs, result.market, result.borrower);

        result.liquidatableAfter = true;
        result.repaidBorrowAssets = repaidBorrowAssets;
        result.seizedCollateralAssets = seizedCollateralAssets;
        result.badDebtAssets = badDebtAssets;
        totals.liquidationFundingAssets += repaidBorrowAssets;
        totals.badDebtAssets += badDebtAssets;
        totals.seizedCollateralAssets += seizedCollateralAssets;
        vm.revertToState(snapshotId);
    }

    function _callLiquidation(address market, address borrower)
        internal
        returns (bool success, bytes memory returnData)
    {
        address borrowToken = IMarket(market).borrowToken();
        _dealToken(borrowToken, SIMULATION_LIQUIDATOR, type(uint128).max);
        vm.startPrank(SIMULATION_LIQUIDATOR);
        require(IERC20(borrowToken).approve(market, type(uint256).max), "Simulation: approve failed");
        (success, returnData) = market.call(abi.encodeCall(IMarketBase.liquidate, (borrower, bytes(""), bytes(""))));
        vm.stopPrank();
    }

    function _isSolventPositionError(bytes memory returnData) internal pure returns (bool) {
        return _revertSelector(returnData)
            == IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector;
    }

    function _liquidationOutcome(Vm.Log[] memory logs, address market, address borrower)
        internal
        pure
        returns (uint256 seizedCollateralAssets, uint256 repaidBorrowAssets, uint256 badDebtAssets)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == market && logs[i].topics.length == 2 && logs[i].topics[0] == LIQUIDATION_EVENT_SIG
                    && address(uint160(uint256(logs[i].topics[1]))) == borrower
            ) {
                (, seizedCollateralAssets,, repaidBorrowAssets,, badDebtAssets,) =
                    abi.decode(logs[i].data, (address, uint256, uint256, uint256, uint256, uint256, uint256));
                return (seizedCollateralAssets, repaidBorrowAssets, badDebtAssets);
            }
        }
        revert("Simulation: liquidation event missing");
    }

    // Low-level call and token-balance helpers.

    function _callFrom(address caller, address target, bytes memory data) internal {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) _bubbleRevert(returnData);
    }

    function _revertSelector(bytes memory returnData) internal pure returns (bytes4 selector) {
        if (returnData.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returnData, 0x20))
        }
    }

    function _bubbleRevert(bytes memory returnData) internal pure {
        if (returnData.length == 0) revert("Simulation: unexpected empty revert");
        assembly ("memory-safe") {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    function _dealToken(address token, address account, uint256 amount) internal {
        simulationStorage.target(token).sig(IERC20.balanceOf.selector).with_key(account).checked_write(amount);
    }
}
