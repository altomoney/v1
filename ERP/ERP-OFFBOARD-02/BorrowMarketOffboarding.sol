// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    BatchAContainParams,
    BatchBReduceLtvParams,
    BatchBSetFixedRateIrmParams,
    BatchCRecoverParams,
    BorrowMarketOffboardingContracts,
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingManifest,
    BorrowMarketOffboardingMarket,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingReport,
    BorrowMarketOffboardingSimulationTotals,
    BorrowMarketOffboardingSchedulePhase,
    BorrowMarketOffboardingSeverity,
    BorrowMarketOffboardingVault
} from "./IBorrowMarketOffboarding.sol";

import {ERPOutputWriter, ERPTransactionBatch} from "../libraries/ERPOutputWriter.sol";
import {ERPVaultQueue, ERPVaultQueuePlan} from "../libraries/ERPVaultQueue.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

interface IPauserState is IPausable {
    function pausers(address account, bytes32 pauseType) external view returns (bool);
}

/// @notice Builds, validates and writes one operational phase of ERP-OFFBOARD-02.
library BorrowMarketOffboarding {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant MAX_LTV_REDUCTION = 0.05 ether;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant MAX_BORROW_RATE_SPY = 8 ether / YEAR;
    uint256 internal constant TERMINAL_STEP_INTERVAL = 1 hours;
    string internal constant ERP_OUTPUT_DIR = "ERP/ERP-OFFBOARD-02/output";

    function runPhase(
        BorrowMarketOffboardingPhase phase,
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input
    ) internal returns (BorrowMarketOffboardingInput memory) {
        BorrowMarketOffboardingContracts memory contracts = input.contracts;

        BorrowMarketOffboardingReport memory report;
        if (phase == BorrowMarketOffboardingPhase.BATCH_A_CONTAIN) {
            report = _prepareContainment(
                BatchAContainParams({
                    freezerSafe: manifest.freezerSafe, markets: manifest.markets, vaults: manifest.vaults
                })
            );
        } else if (phase == BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM) {
            address ownerFixedRateIrmFactory = contracts.ownerFixedRateIrmFactory;
            if (ownerFixedRateIrmFactory == address(0)) {
                ownerFixedRateIrmFactory = _deployOwnerFixedRateIrmFactory(contracts.timelock);
                input.contracts.ownerFixedRateIrmFactory = ownerFixedRateIrmFactory;
            }
            report = _prepareFixedRateIrmAttachment(
                BatchBSetFixedRateIrmParams({
                    timelockSafe: manifest.timelockSafe,
                    timelock: contracts.timelock,
                    ownerFixedRateIrmFactory: ownerFixedRateIrmFactory,
                    version: manifest.fixedRateIrmVersion,
                    markets: manifest.markets
                })
            );
        } else if (phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            report = prepareRateAndLtvReduction(manifest, input);
        } else if (phase == BorrowMarketOffboardingPhase.BATCH_C_RECOVER) {
            report = _prepareRecovery(
                BatchCRecoverParams({
                    timelockSafe: manifest.timelockSafe,
                    timelock: contracts.timelock,
                    marketRegistry: contracts.marketRegistry,
                    altoAdapter: contracts.altoAdapter,
                    liquidationPeriphery: contracts.liquidationPeriphery,
                    markets: manifest.markets,
                    vaults: manifest.vaults
                })
            );
        } else {
            revert("ERP: invalid phase");
        }

        _writePhaseArtifacts(phase, manifest, input, report);
        return input;
    }

    /// @notice Builds the exact Batch B rate/LTV calls without writing operational artifacts.
    function prepareRateAndLtvReduction(
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input
    ) internal view returns (BorrowMarketOffboardingReport memory report) {
        // previousAprFloorSpy is zero for step 1 because no prior correction exists.
        (uint256 aprFloorSpy, uint256 previousAprFloorSpy) =
            _validateCorrectionSchedule(manifest, input.contracts.timelock);
        report = _prepareRateAndLtvReduction(
            BatchBReduceLtvParams({
                timelockSafe: manifest.timelockSafe,
                timelock: input.contracts.timelock,
                aprFloorSpy: aprFloorSpy,
                previousAprFloorSpy: previousAprFloorSpy,
                lastStepExecutedAt: manifest.lastStepExecutedAt,
                lastOperationId: manifest.lastOperationId,
                markets: manifest.markets
            })
        );
    }

    /// @notice Rejects a simulated Batch B outcome outside the governance-approved limits.
    function validateSimulationLimits(
        BorrowMarketOffboardingSimulationTotals memory totals,
        BorrowMarketOffboardingMarket memory market
    ) internal pure {
        require(
            totals.liquidationFundingAssets <= market.maxLiquidationFundingAssets, "Simulation: funding limit exceeded"
        );
        require(totals.badDebtAssets <= market.maxBadDebtAssets, "Simulation: bad debt limit exceeded");
        require(totals.supplierLossAssets <= market.maxSupplierLossAssets, "Simulation: supplier loss limit exceeded");
        require(totals.protocolLossAssets <= market.maxProtocolLossAssets, "Simulation: protocol loss limit exceeded");
    }

    function _deployOwnerFixedRateIrmFactory(address timelock) private returns (address) {
        _requireNonZero(timelock, "Factory deploy: invalid Timelock");

        OwnerFixedRateIrmFactory factory = new OwnerFixedRateIrmFactory(timelock);

        console2.log("OwnerFixedRateIrmFactory:", address(factory));
        console2.log("Owner:", timelock);
        console2.log("Manual update required in addresses.json: .contracts.ownerFixedRateIrmFactory");

        return address(factory);
    }

    /// @notice Returns the artifact directory for the selected operational phase.
    function artifactDirectory(BorrowMarketOffboardingPhase phase, BorrowMarketOffboardingManifest memory manifest)
        internal
        pure
        returns (string memory)
    {
        string memory outputDirectory = string.concat(ERP_OUTPUT_DIR, "/", manifest.activationId);
        if (
            phase == BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM
                || phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV
        ) {
            outputDirectory = string.concat(
                outputDirectory, "/severity-", _severityName(manifest.severity), "/step-", vm.toString(manifest.step)
            );
        }
        return string.concat(outputDirectory, "/source-block-", vm.toString(manifest.sourceBlock));
    }

    function _severityName(BorrowMarketOffboardingSeverity severity) private pure returns (string memory) {
        if (severity == BorrowMarketOffboardingSeverity.MEDIUM) return "medium";
        if (severity == BorrowMarketOffboardingSeverity.HIGH) return "high";
        if (severity == BorrowMarketOffboardingSeverity.CRITICAL) return "critical";
        revert("ERP: invalid severity");
    }

    function vaultCuratorFileName(address vault) internal pure returns (string memory) {
        return string.concat("batch-a-vault-", vm.toString(vault), "-curator-safe.json");
    }

    function vaultAllocatorFileName(BorrowMarketOffboardingPhase phase, address vault)
        internal
        pure
        returns (string memory)
    {
        if (phase == BorrowMarketOffboardingPhase.BATCH_A_CONTAIN) {
            return string.concat("batch-a-vault-", vm.toString(vault), "-allocator.json");
        }
        if (phase == BorrowMarketOffboardingPhase.BATCH_C_RECOVER) {
            return string.concat("batch-c-vault-", vm.toString(vault), "-allocator.json");
        }
        revert("ERP: phase has no allocator plan");
    }

    function _prepareContainment(BatchAContainParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        _requireNonZero(params.freezerSafe, "Batch A: zero freezer Safe");
        uint256 marketCount = params.markets.length;
        uint256 freezerCallCount;
        for (uint256 i; i < marketCount; ++i) {
            IPauserState market = IPauserState(params.markets[i].market);
            require(!market.paused(PAUSE_TYPE), "Batch A: market paused");
            if (!market.paused(FROZEN_TYPE)) {
                require(market.pausers(params.freezerSafe, FROZEN_TYPE), "Batch A: Safe is not freezer");
                ++freezerCallCount;
            }
        }

        report.freezerBatch = ERPOutputWriter.newBatch(params.freezerSafe, freezerCallCount);
        uint256 freezerCallIndex;
        for (uint256 i; i < marketCount; ++i) {
            address market = params.markets[i].market;
            if (IPauserState(market).paused(FROZEN_TYPE)) continue;
            freezerCallIndex = ERPOutputWriter.addBatchCall(
                report.freezerBatch, freezerCallIndex, market, abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true))
            );
        }
        assert(freezerCallIndex == freezerCallCount);

        address[] memory affectedMarkets = _marketAddresses(params.markets);
        uint256 vaultCount = params.vaults.length;
        report.vaultCuratorBatches = new ERPTransactionBatch[](vaultCount);
        report.vaultAllocatorPlans = new ERPVaultQueuePlan[](vaultCount);
        for (uint256 vaultIndex; vaultIndex < vaultCount; ++vaultIndex) {
            BorrowMarketOffboardingVault memory configuredVault = params.vaults[vaultIndex];
            address vault = configuredVault.vault;
            _requireNonZero(vault, "Batch A: invalid Vault");
            ERPVaultQueue.validateAllocator(vault, configuredVault.allocator, "Batch A: unauthorized Vault allocator");

            address vaultCurator = IAltoVaultBase(vault).curator();
            _requireNonZero(vaultCurator, "Batch A: zero Vault curator");
            uint256 curatorCallCount;
            for (uint256 marketIndex; marketIndex < marketCount; ++marketIndex) {
                address market = params.markets[marketIndex].market;
                MarketConfig memory marketConfig = IAltoVault(vault).config(market);
                if (IAltoVault(vault).pendingCap(market).validAt != 0) ++curatorCallCount;
                if (marketConfig.removableAt != 0) ++curatorCallCount;
                if (marketConfig.cap != 0) ++curatorCallCount;
            }

            ERPTransactionBatch memory curatorBatch = ERPOutputWriter.newBatch(vaultCurator, curatorCallCount);
            uint256 callIndex;
            for (uint256 marketIndex; marketIndex < marketCount; ++marketIndex) {
                address market = params.markets[marketIndex].market;
                if (IAltoVault(vault).pendingCap(market).validAt != 0) {
                    callIndex = ERPOutputWriter.addBatchCall(
                        curatorBatch, callIndex, vault, abi.encodeCall(IAltoVaultBase.revokePendingCap, (market))
                    );
                }

                MarketConfig memory marketConfig = IAltoVault(vault).config(market);
                if (marketConfig.removableAt != 0) {
                    callIndex = ERPOutputWriter.addBatchCall(
                        curatorBatch,
                        callIndex,
                        vault,
                        abi.encodeCall(IAltoVaultBase.revokePendingMarketRemoval, (market))
                    );
                }
                if (marketConfig.cap != 0) {
                    callIndex = ERPOutputWriter.addBatchCall(
                        curatorBatch, callIndex, vault, abi.encodeCall(IAltoVaultBase.submitCap, (market, 0))
                    );
                }
            }
            assert(callIndex == curatorCallCount);
            report.vaultCuratorBatches[vaultIndex] = curatorBatch;
            report.vaultAllocatorPlans[vaultIndex] = ERPVaultQueue.setSupplyQueuePlan(
                vault, configuredVault.allocator, affectedMarkets, configuredVault.replacementMarkets
            );
        }
    }

    function _prepareFixedRateIrmAttachment(BatchBSetFixedRateIrmParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        address factoryAddress = params.ownerFixedRateIrmFactory;
        _requireNonZero(factoryAddress, "Batch B: invalid IRM factory");

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(factoryAddress);
        require(factory.owner() == params.timelock, "Batch B: Timelock does not own factory");
        require(factory.pendingOwner() == address(0), "Batch B: factory ownership transfer pending");

        uint256 marketCount = params.markets.length;
        report = _newTimelockReport(params.timelockSafe, params.timelock, marketCount * 2, bytes32(0));

        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            uint256 borrowRateSpy = params.markets[i].fixedRateSpy;
            _validateFrozenAndNotPaused(market);
            require(_hasDebt(market), "Batch B: debt targets reached");
            require(borrowRateSpy <= MAX_BORROW_RATE_SPY, "Batch B: rate above IRM maximum");

            address predictedIrm = factory.predictIrmAddress(market, params.version, borrowRateSpy);

            ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                i,
                factoryAddress,
                abi.encodeCall(OwnerFixedRateIrmFactory.deploy, (market, params.version, borrowRateSpy))
            );
            ERPOutputWriter.addBatchCall(
                report.timelockBatch, marketCount + i, market, abi.encodeCall(IMarketBase.setIrm, (predictedIrm, false))
            );
        }
    }

    function _prepareRateAndLtvReduction(BatchBReduceLtvParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        uint256 marketCount;
        for (uint256 i; i < params.markets.length; ++i) {
            if (_hasDebt(params.markets[i].market)) ++marketCount;
        }
        require(marketCount != 0, "Batch B: debt targets reached");
        report = _newTimelockReport(params.timelockSafe, params.timelock, marketCount * 3, params.lastOperationId);

        uint256 callIndex;
        for (uint256 i; i < params.markets.length; ++i) {
            IMarketBase market = IMarketBase(params.markets[i].market);
            if (!_hasDebt(address(market))) continue;

            uint256 borrowRateSpy = params.markets[i].correctionRateSpy;
            _validateFrozenAndNotPaused(address(market));
            uint256 ltvReduction = params.markets[i].ltvReduction;
            require(ltvReduction <= MAX_LTV_REDUCTION, "Batch B: LTV reduction above maximum");

            address fixedRateIrm = market.irm();
            address liquidationEngine = market.liquidationEngine();
            _validateRateCorrection(params, address(market), fixedRateIrm, liquidationEngine, borrowRateSpy);
            (uint256 reducedMarketMaxLtv, LiquidationConfiguration memory liquidationConfiguration) =
                _reducedLtvConfiguration(market, liquidationEngine, ltvReduction);

            ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                callIndex,
                fixedRateIrm,
                abi.encodeCall(FixedRateIrm.setBorrowRate, (borrowRateSpy))
            );
            ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                callIndex + 1,
                address(market),
                abi.encodeCall(IMarketBase.setMaxLtv, (reducedMarketMaxLtv))
            );
            ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                callIndex + 2,
                liquidationEngine,
                abi.encodeCall(
                    IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (liquidationConfiguration)
                )
            );
            callIndex += 3;
        }
    }

    function _validateRateCorrection(
        BatchBReduceLtvParams memory params,
        address market,
        address fixedRateIrm,
        address liquidationEngine,
        uint256 borrowRateSpy
    ) private view {
        require(IIrm(fixedRateIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Batch B: IRM is not fixed-rate");
        require(FixedRateIrm(fixedRateIrm).market() == market, "Batch B: IRM not dedicated");
        require(FixedRateIrm(fixedRateIrm).owner() == params.timelock, "Batch B: Timelock does not own IRM");
        require(
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).market() == market, "Batch B: wrong liquidation engine"
        );
        require(
            Ownable(liquidationEngine).owner() == params.timelock, "Batch B: Timelock does not own liquidation engine"
        );
        require(borrowRateSpy <= FixedRateIrm(fixedRateIrm).MAX_BORROW_RATE(), "Batch B: rate above IRM maximum");
        require(borrowRateSpy >= params.aprFloorSpy, "Batch B: rate below schedule APR floor");

        (uint256 currentBorrowRate, uint48 lastRateUpdate) = FixedRateIrm(fixedRateIrm).irState();
        require(currentBorrowRate >= params.previousAprFloorSpy, "Batch B: previous step not executed");
        require(borrowRateSpy >= currentBorrowRate, "Batch B: rate below current rate");
        if (params.lastStepExecutedAt != 0) {
            require(lastRateUpdate >= params.lastStepExecutedAt, "Batch B: prior execution not reflected in IRM");
        }
    }

    function _reducedLtvConfiguration(IMarketBase market, address liquidationEngine, uint256 ltvReduction)
        private
        view
        returns (uint256 reducedMarketMaxLtv, LiquidationConfiguration memory configuration)
    {
        configuration = IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        uint256 currentMarketMaxLtv = market.maxLtv();
        reducedMarketMaxLtv = _saturatingSub(currentMarketMaxLtv, ltvReduction);
        configuration.maxLiquidationLtv = _saturatingSub(configuration.maxLiquidationLtv, ltvReduction);
        configuration.ltvForCompleteLiquidation = _saturatingSub(configuration.ltvForCompleteLiquidation, ltvReduction);
        require(
            reducedMarketMaxLtv <= configuration.maxLiquidationLtv
                && configuration.maxLiquidationLtv <= configuration.ltvForCompleteLiquidation,
            "Batch B: invalid LTV order"
        );
    }

    /// @dev Validates the immutable ERP timetable before any correction batch is built.
    /// @return aprFloorSpy Minimum per-second borrow rate for the requested step.
    /// @return previousAprFloorSpy Minimum per-second borrow rate expected from the prior step.
    function _validateCorrectionSchedule(BorrowMarketOffboardingManifest memory manifest, address timelock)
        private
        view
        returns (uint256 aprFloorSpy, uint256 previousAprFloorSpy)
    {
        require(manifest.t0 <= block.timestamp, "Batch B: T0 is in the future");
        require(manifest.lastExecutedStep + 1 == manifest.step, "Batch B: steps must be sequential");

        if (manifest.schedulePhase == BorrowMarketOffboardingSchedulePhase.SCHEDULED) {
            (uint256 offset, uint256 aprFloor) = _scheduledStep(manifest.severity, manifest.step);
            require(block.timestamp >= manifest.t0 + offset, "Batch B: scheduled step is not due");

            // Step 1 is the first scheduled correction after T0, so no prior execution should exist.
            if (manifest.step == 1) {
                require(manifest.lastStepExecutedAt == 0, "Batch B: unexpected prior step timestamp");
                require(manifest.lastOperationId == bytes32(0), "Batch B: unexpected prior operation");
            } else {
                require(manifest.lastStepExecutedAt != 0, "Batch B: missing prior execution timestamp");
                require(manifest.lastStepExecutedAt <= block.timestamp, "Batch B: prior execution is in the future");
                (, uint256 previousAprFloor) = _scheduledStep(manifest.severity, manifest.step - 1);
                _validatePriorOperationExecuted(timelock, manifest.lastOperationId);
                previousAprFloorSpy = _aprToSpy(previousAprFloor);
            }

            aprFloorSpy = _aprToSpy(aprFloor);
        } else if (manifest.schedulePhase == BorrowMarketOffboardingSchedulePhase.TERMINAL) {
            require(manifest.lastStepExecutedAt != 0, "Batch B: missing prior execution timestamp");
            require(manifest.lastStepExecutedAt <= block.timestamp, "Batch B: prior execution is in the future");
            require(
                block.timestamp >= manifest.t0 + _terminalOffset(manifest.severity),
                "Batch B: terminal phase is not due"
            );
            require(
                block.timestamp >= manifest.lastStepExecutedAt + TERMINAL_STEP_INTERVAL,
                "Batch B: terminal step interval not elapsed"
            );
            _validateDebtRemains(manifest.markets);
            _validatePriorOperationExecuted(timelock, manifest.lastOperationId);

            uint256 terminalAprFloor = _terminalAprFloor(manifest.severity);
            aprFloorSpy = _aprToSpy(terminalAprFloor);
            previousAprFloorSpy = aprFloorSpy;
        } else {
            revert("Batch B: invalid schedule phase");
        }
    }

    function _scheduledStep(BorrowMarketOffboardingSeverity severity, uint256 step)
        private
        pure
        returns (uint256 offset, uint256 aprFloor)
    {
        if (severity == BorrowMarketOffboardingSeverity.MEDIUM) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (7 days, 0.2 ether);
            if (step == 3) return (14 days, 0.4 ether);
            if (step == 4) return (21 days, 0.8 ether);
        } else if (severity == BorrowMarketOffboardingSeverity.HIGH) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (4 days, 0.2 ether);
            if (step == 3) return (7 days, 0.4 ether);
            if (step == 4) return (10 days, 0.8 ether);
        } else if (severity == BorrowMarketOffboardingSeverity.CRITICAL) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (2 days, 0.2 ether);
            if (step == 3) return (3 days, 0.4 ether);
            if (step == 4) return (4 days, 0.8 ether);
            if (step == 5) return (5 days, 1.6 ether);
            if (step == 6) return (6 days, 3.2 ether);
        } else {
            revert("Batch B: invalid severity");
        }

        revert("Batch B: invalid scheduled step");
    }

    function _terminalOffset(BorrowMarketOffboardingSeverity severity) private pure returns (uint256) {
        if (severity == BorrowMarketOffboardingSeverity.MEDIUM) return 28 days;
        if (severity == BorrowMarketOffboardingSeverity.HIGH) return 14 days;
        if (severity == BorrowMarketOffboardingSeverity.CRITICAL) return 7 days;
        revert("Batch B: invalid severity");
    }

    function _terminalAprFloor(BorrowMarketOffboardingSeverity severity) private pure returns (uint256) {
        // Carry forward the final scheduled APR floor: 80% for Medium/High and 320% for Critical.
        return severity == BorrowMarketOffboardingSeverity.CRITICAL ? 3.2 ether : 0.8 ether;
    }

    function _aprToSpy(uint256 apr) private pure returns (uint256) {
        return apr / YEAR;
    }

    function _validateDebtRemains(BorrowMarketOffboardingMarket[] memory markets) private view {
        for (uint256 i; i < markets.length; ++i) {
            if (_hasDebt(markets[i].market)) return;
        }
        revert("Batch B: debt targets reached");
    }

    function _hasDebt(address market) private view returns (bool) {
        Balance memory borrowed = IMarket(market).totalBorrowed();
        return borrowed.assets != 0 || borrowed.shares != 0;
    }

    function _saturatingSub(uint256 value, uint256 reduction) private pure returns (uint256) {
        return value > reduction ? value - reduction : 0;
    }

    function _validatePriorOperationExecuted(address timelock, bytes32 operationId) private view {
        require(operationId != bytes32(0), "Batch B: missing prior operation");
        require(
            TimelockController(payable(timelock)).isOperationDone(operationId), "Batch B: prior operation not executed"
        );
    }

    function _prepareRecovery(BatchCRecoverParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        _validateRecoveryConfiguration(params);
        _validateZeroDebt(params.markets);
        _validateFinalRemovalState(params);

        bool queueUpdateRequired;
        (report.vaultAllocatorPlans, queueUpdateRequired) = _prepareWithdrawQueuePlans(params.vaults, params.markets);
        if (queueUpdateRequired) {
            report.timelockBatch = ERPOutputWriter.newBatch(params.timelockSafe, 0);
            report.timelockDelay = TimelockController(payable(params.timelock)).getMinDelay();
            return report;
        }

        _validateVaultRemovalComplete(params.markets, params.vaults);
        uint256 callCount = _countRecoveryCalls(params);
        BorrowMarketOffboardingReport memory timelockReport =
            _newTimelockReport(params.timelockSafe, params.timelock, callCount, bytes32(0));
        report.timelockBatch = timelockReport.timelockBatch;
        report.timelockDelay = timelockReport.timelockDelay;
        report.predecessor = timelockReport.predecessor;

        uint256 callIndex = _appendLeverageRemovalCalls(params, report.timelockBatch, 0);
        callIndex = _appendLiquidationRemovalCalls(params, report.timelockBatch, callIndex);
        callIndex = _appendRegistryRemovalCalls(params, report.timelockBatch, callIndex);
        assert(callIndex == callCount);
    }

    function _prepareWithdrawQueuePlans(
        BorrowMarketOffboardingVault[] memory configuredVaults,
        BorrowMarketOffboardingMarket[] memory markets
    ) private view returns (ERPVaultQueuePlan[] memory plans, bool queueUpdateRequired) {
        address[] memory affectedMarkets = _marketAddresses(markets);
        plans = new ERPVaultQueuePlan[](configuredVaults.length);

        for (uint256 vaultIndex; vaultIndex < configuredVaults.length; ++vaultIndex) {
            BorrowMarketOffboardingVault memory configuredVault = configuredVaults[vaultIndex];
            plans[vaultIndex] = ERPVaultQueue.updateWithdrawQueuePlan(
                configuredVault.vault, configuredVault.allocator, affectedMarkets, "Batch C"
            );
            if (plans[vaultIndex].data.length != 0) queueUpdateRequired = true;
        }
    }

    function _countRecoveryCalls(BatchCRecoverParams memory params) private view returns (uint256 callCount) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            AltoLeverage leverage = AltoLeverage(params.markets[i].leverage);
            IAltoLeverageSwapper leverageSwapper = leverage.swapper();

            if (leverage.supportedMarkets(market)) ++callCount;
            if (IMarket(market).authorizedCallbacks(address(leverage))) ++callCount;
            if (leverageSwapper.isWhitelisted(address(leverage))) ++callCount;
            if (ILiquidationPeripheryBase(params.liquidationPeriphery).supportedMarkets(market)) ++callCount;
            if (IMarket(market).authorizedLiquidationPeriphery(params.liquidationPeriphery)) ++callCount;
            if (IMarketRegistry(params.marketRegistry).isBorrowMarket(market)) ++callCount;
        }
    }

    function _appendLeverageRemovalCalls(
        BatchCRecoverParams memory params,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private view returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            AltoLeverage leverage = AltoLeverage(params.markets[i].leverage);

            if (leverage.supportedMarkets(market)) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch, callIndex, address(leverage), abi.encodeCall(AltoLeverage.setMarket, (market, false))
                );
            }
            if (IMarket(market).authorizedCallbacks(address(leverage))) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    market,
                    abi.encodeCall(IMarketBase.setAuthorizedCallback, (address(leverage), false))
                );
            }

            IAltoLeverageSwapper leverageSwapper = leverage.swapper();
            if (leverageSwapper.isWhitelisted(address(leverage))) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    address(leverageSwapper),
                    abi.encodeCall(IAltoLeverageSwapper.setWhitelisted, (address(leverage), false))
                );
            }
        }
        return callIndex;
    }

    function _appendLiquidationRemovalCalls(
        BatchCRecoverParams memory params,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private view returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            if (ILiquidationPeripheryBase(params.liquidationPeriphery).supportedMarkets(market)) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    params.liquidationPeriphery,
                    abi.encodeCall(ILiquidationPeripheryBase.setSupportedMarket, (market, false))
                );
            }
            if (IMarket(market).authorizedLiquidationPeriphery(params.liquidationPeriphery)) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    market,
                    abi.encodeCall(IMarketBase.setAuthorizedLiquidationPeriphery, (params.liquidationPeriphery, false))
                );
            }
        }
        return callIndex;
    }

    function _appendRegistryRemovalCalls(
        BatchCRecoverParams memory params,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private view returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            if (!IMarketRegistry(params.marketRegistry).isBorrowMarket(market)) continue;

            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, params.marketRegistry, abi.encodeCall(IMarketRegistry.removeBorrowMarket, (market))
            );
        }
        return callIndex;
    }

    function _writePhaseArtifacts(
        BorrowMarketOffboardingPhase phase,
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input,
        BorrowMarketOffboardingReport memory report
    ) private {
        string memory outputDirectory = artifactDirectory(phase, manifest);
        address timelock = input.contracts.timelock;
        vm.createDir(outputDirectory, true);

        if (phase == BorrowMarketOffboardingPhase.BATCH_A_CONTAIN) {
            ERPOutputWriter.writeOptionalSafeBatch(
                outputDirectory,
                "batch-a-freeze-safe.json",
                "ERP-OFFBOARD-02 - Batch A Freeze Borrow Markets",
                report.freezerBatch
            );

            string memory legacyCuratorPath = string.concat(outputDirectory, "/batch-a-vault-curator-safe.json");
            ERPOutputWriter.removeIfExists(legacyCuratorPath);

            assert(report.vaultCuratorBatches.length == manifest.vaults.length);
            for (uint256 i; i < manifest.vaults.length; ++i) {
                address vault = manifest.vaults[i].vault;
                ERPOutputWriter.writeOptionalSafeBatch(
                    outputDirectory,
                    vaultCuratorFileName(vault),
                    string.concat("ERP-OFFBOARD-02 - Batch A Zero Borrow Market Caps - ", vm.toString(vault)),
                    report.vaultCuratorBatches[i]
                );
                ERPVaultQueue.writeOptionalContainmentPlan(
                    outputDirectory,
                    vaultAllocatorFileName(phase, vault),
                    manifest.sourceBlock,
                    report.vaultAllocatorPlans[i]
                );
            }
            return;
        }

        if (phase == BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM) {
            ERPOutputWriter.writeTimelockPair(
                outputDirectory,
                "batch-b-fixed-rate-irm",
                "ERP-OFFBOARD-02 - Batch B Deploy and Attach Fixed-Rate IRMs",
                timelock,
                report.timelockBatch,
                report.timelockDelay,
                report.predecessor
            );
            return;
        }

        if (phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            ERPOutputWriter.writeTimelockPair(
                outputDirectory,
                "batch-b-irm-and-ltv-update",
                "ERP-OFFBOARD-02 - Batch B Update IRM Rates and Apply Approved LTV Reduction",
                timelock,
                report.timelockBatch,
                report.timelockDelay,
                report.predecessor
            );
            return;
        }

        if (phase == BorrowMarketOffboardingPhase.BATCH_C_RECOVER) {
            assert(report.vaultAllocatorPlans.length == manifest.vaults.length);
            for (uint256 i; i < manifest.vaults.length; ++i) {
                ERPVaultQueue.writeOptionalWithdrawQueuePlan(
                    outputDirectory,
                    vaultAllocatorFileName(phase, manifest.vaults[i].vault),
                    manifest.sourceBlock,
                    report.vaultAllocatorPlans[i]
                );
            }
            ERPOutputWriter.writeOptionalTimelockPair(
                outputDirectory,
                "batch-c-final-removal",
                "ERP-OFFBOARD-02 - Batch C Final Registry and Integration Removal",
                timelock,
                report.timelockBatch,
                report.timelockDelay,
                report.predecessor
            );
        }
    }

    function _validateFrozenAndNotPaused(address market) private view {
        require(IMarketBase(market).paused(FROZEN_TYPE), "Batch B: market not frozen");
        require(!IMarketBase(market).paused(PAUSE_TYPE), "Batch B: market paused");
    }

    function _validateRecoveryConfiguration(BatchCRecoverParams memory params) private view {
        _requireNonZero(params.marketRegistry, "Batch C: zero registry");
        _requireNonZero(params.altoAdapter, "Batch C: zero adapter");
        _requireNonZero(params.liquidationPeriphery, "Batch C: zero liquidation periphery");

        for (uint256 i; i < params.markets.length; ++i) {
            _requireNonZero(params.markets[i].leverage, "Batch C: zero leverage");
        }
        for (uint256 i; i < params.vaults.length; ++i) {
            _requireNonZero(params.vaults[i].vault, "Batch C: zero Vault");
            ERPVaultQueue.validateAllocator(
                params.vaults[i].vault, params.vaults[i].allocator, "Batch C: unauthorized Vault allocator"
            );
            for (uint256 j; j < i; ++j) {
                require(params.vaults[i].vault != params.vaults[j].vault, "Batch C: duplicate Vault");
            }
        }
    }

    function _validateZeroDebt(BorrowMarketOffboardingMarket[] memory markets) private view {
        for (uint256 i; i < markets.length; ++i) {
            require(!_hasDebt(markets[i].market), "Batch C: market debt remains");
        }
    }

    function _validateVaultRemovalComplete(
        BorrowMarketOffboardingMarket[] memory markets,
        BorrowMarketOffboardingVault[] memory configuredVaults
    ) private view {
        for (uint256 vaultIndex; vaultIndex < configuredVaults.length; ++vaultIndex) {
            IAltoVault vault = IAltoVault(configuredVaults[vaultIndex].vault);
            address[] memory supplyQueue = ERPVaultQueue.supplyQueue(vault);
            address[] memory withdrawQueue = ERPVaultQueue.withdrawQueue(vault);

            for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
                address market = markets[marketIndex].market;
                MarketConfig memory vaultConfig = vault.config(market);
                PendingUint192 memory pendingCap = vault.pendingCap(market);

                require(
                    IMarket(market).position(address(vault)).supplyShares == 0, "Batch C: Vault market supply remains"
                );
                require(vault.quarantinedAssets(market) == 0, "Batch C: Vault market assets quarantined");
                require(vaultConfig.cap == 0, "Batch C: Vault cap remains");
                require(!vaultConfig.enabled, "Batch C: Vault market still enabled");
                require(vaultConfig.removableAt == 0, "Batch C: pending Vault removal remains");
                require(pendingCap.validAt == 0, "Batch C: pending Vault cap remains");
                require(!ERPVaultQueue.contains(supplyQueue, market), "Batch C: market remains in supply queue");
                require(!ERPVaultQueue.contains(withdrawQueue, market), "Batch C: market remains in withdraw queue");
            }
        }
    }

    function _validateFinalRemovalState(BatchCRecoverParams memory params) private view {
        require(Ownable(params.marketRegistry).owner() == params.timelock, "Batch C: Timelock does not own registry");
        require(
            Ownable(params.liquidationPeriphery).owner() == params.timelock,
            "Batch C: Timelock does not own liquidation periphery"
        );

        for (uint256 i; i < params.markets.length; ++i) {
            IMarket market = IMarket(params.markets[i].market);
            AltoLeverage leverage = AltoLeverage(params.markets[i].leverage);
            IAltoLeverageSwapper leverageSwapper = leverage.swapper();

            require(market.paused(FROZEN_TYPE), "Batch C: market not frozen");
            require(!market.paused(PAUSE_TYPE), "Batch C: market paused");
            _requireNonZero(market.oracle(), "Batch C: market oracle unavailable");
            require(
                AdapterContractApproval(params.altoAdapter).isApprovedContract(address(market)),
                "Batch C: adapter route unavailable"
            );
            require(Ownable(address(market)).owner() == params.timelock, "Batch C: Timelock does not own market");
            require(Ownable(address(leverage)).owner() == params.timelock, "Batch C: Timelock does not own leverage");
            _requireNonZero(address(leverageSwapper), "Batch C: zero leverage swapper");
            require(
                Ownable(address(leverageSwapper)).owner() == params.timelock,
                "Batch C: Timelock does not own leverage swapper"
            );
        }
    }

    function _marketAddresses(BorrowMarketOffboardingMarket[] memory markets)
        private
        pure
        returns (address[] memory addresses)
    {
        addresses = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            addresses[i] = markets[i].market;
        }
    }

    function _newTimelockReport(address safe, address timelock, uint256 callCount, bytes32 predecessor)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        report.timelockBatch = ERPOutputWriter.newBatch(safe, callCount);
        report.timelockDelay = TimelockController(payable(timelock)).getMinDelay();
        report.predecessor = predecessor;
    }

    function _requireNonZero(address value, string memory errorMessage) private pure {
        require(value != address(0), errorMessage);
    }
}
