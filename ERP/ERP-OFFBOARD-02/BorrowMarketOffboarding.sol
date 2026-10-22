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
    BorrowMarketOffboardingVault
} from "./IBorrowMarketOffboarding.sol";

import {ERPOutputWriter, ERPTransactionBatch} from "../libraries/ERPOutputWriter.sol";
import {ERPMarketOffboarding} from "../libraries/ERPMarketOffboarding.sol";
import {ERPVaultQueue, ERPVaultQueuePlan} from "../libraries/ERPVaultQueue.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Vm} from "forge-std/Vm.sol";

interface IPauserState is IPausable {
    function pausers(address account, bytes32 pauseType) external view returns (bool);
}

/// @notice Builds, validates and writes one operational phase of ERP-OFFBOARD-02.
library BorrowMarketOffboarding {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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
                ownerFixedRateIrmFactory = ERPMarketOffboarding.deployOwnerFixedRateIrmFactory(contracts.timelock);
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
        ERPMarketOffboarding.validateCommonSimulationLimits(
            totals.liquidationFundingAssets,
            totals.badDebtAssets,
            market.maxLiquidationFundingAssets,
            market.maxBadDebtAssets
        );
        require(totals.supplierLossAssets <= market.maxSupplierLossAssets, "Simulation: supplier loss limit exceeded");
        require(totals.protocolLossAssets <= market.maxProtocolLossAssets, "Simulation: protocol loss limit exceeded");
    }

    /// @notice Returns the artifact directory for the selected operational phase.
    function artifactDirectory(BorrowMarketOffboardingPhase phase, BorrowMarketOffboardingManifest memory manifest)
        internal
        pure
        returns (string memory)
    {
        return ERPMarketOffboarding.artifactDirectory(
            ERP_OUTPUT_DIR,
            manifest.activationId,
            uint8(phase),
            uint8(manifest.severity),
            manifest.step,
            manifest.sourceBlock
        );
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
        for (uint256 i; i < marketCount; ++i) {
            IPauserState market = IPauserState(params.markets[i].market);
            require(!market.paused(PAUSE_TYPE), "Batch A: market paused");
            if (!market.paused(FROZEN_TYPE)) {
                require(market.pausers(params.freezerSafe, FROZEN_TYPE), "Batch A: Safe is not freezer");
            }
        }

        report.freezerBatch =
            ERPMarketOffboarding.buildFreezeBatch(params.freezerSafe, _marketAddresses(params.markets));

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
                vault,
                configuredVault.allocator,
                affectedMarkets,
                configuredVault.replacementMarkets,
                configuredVault.reallocationBufferAssets
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

        (report.timelockBatch, report.timelockDelay) = ERPMarketOffboarding.buildFixedRateBatch(
            params.timelockSafe, params.timelock, factoryAddress, params.version, _fixedRateMarkets(params.markets)
        );
    }

    function _prepareRateAndLtvReduction(BatchBReduceLtvParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        uint256 marketCount = ERPMarketOffboarding.debtBearingMarketCount(_marketAddresses(params.markets));
        require(marketCount != 0, "Batch B: debt targets reached");
        report = _newTimelockReport(params.timelockSafe, params.timelock, marketCount * 3, params.lastOperationId);

        uint256 callIndex;
        for (uint256 i; i < params.markets.length; ++i) {
            IMarketBase market = IMarketBase(params.markets[i].market);
            if (!ERPMarketOffboarding.hasDebt(address(market))) continue;

            uint256 borrowRateSpy = params.markets[i].correctionRateSpy;
            ERPMarketOffboarding.validateFrozenAndNotPaused(address(market), "Batch B");
            uint256 ltvReduction = params.markets[i].ltvReduction;
            ERPMarketOffboarding.validateLtvReduction(ltvReduction);

            address fixedRateIrm = market.irm();
            address liquidationEngine = market.liquidationEngine();
            _validateRateCorrection(params, address(market), fixedRateIrm, liquidationEngine, borrowRateSpy);
            (uint256 reducedMarketMaxLtv, LiquidationConfiguration memory liquidationConfiguration) =
                ERPMarketOffboarding.reducedLtvConfiguration(address(market), liquidationEngine, ltvReduction);

            callIndex =
                ERPMarketOffboarding.appendRateUpdateCall(report.timelockBatch, callIndex, fixedRateIrm, borrowRateSpy);
            callIndex = ERPMarketOffboarding.appendLtvUpdateCalls(
                report.timelockBatch,
                callIndex,
                address(market),
                liquidationEngine,
                reducedMarketMaxLtv,
                liquidationConfiguration
            );
        }
    }

    function _validateRateCorrection(
        BatchBReduceLtvParams memory params,
        address market,
        address fixedRateIrm,
        address liquidationEngine,
        uint256 borrowRateSpy
    ) private view {
        ERPMarketOffboarding.validateDedicatedFixedRateIrm(market, fixedRateIrm);
        require(FixedRateIrm(fixedRateIrm).owner() == params.timelock, "Batch B: Timelock does not own IRM");
        ERPMarketOffboarding.validateLiquidationEngine(market, liquidationEngine);
        require(
            Ownable(liquidationEngine).owner() == params.timelock, "Batch B: Timelock does not own liquidation engine"
        );
        ERPMarketOffboarding.validateCorrectionRate(
            fixedRateIrm, borrowRateSpy, params.aprFloorSpy, params.previousAprFloorSpy, params.lastStepExecutedAt
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
        return ERPMarketOffboarding.validateCorrectionSchedule(
            ERPMarketOffboarding.ScheduleParams({
                severity: uint8(manifest.severity),
                schedulePhase: uint8(manifest.schedulePhase),
                t0: manifest.t0,
                step: manifest.step,
                lastExecutedStep: manifest.lastExecutedStep,
                lastStepExecutedAt: manifest.lastStepExecutedAt,
                lastOperationId: manifest.lastOperationId
            }),
            timelock,
            _marketAddresses(manifest.markets)
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
        ERPMarketOffboarding.RecoveryMarket[] memory markets = _recoveryMarkets(params.markets);
        (ERPMarketOffboarding.RecoveryIntegrationState[] memory integrations, uint256 callCount) = ERPMarketOffboarding.loadRecoveryIntegrationStates(
            markets, params.liquidationPeriphery, params.marketRegistry, false
        );
        BorrowMarketOffboardingReport memory timelockReport =
            _newTimelockReport(params.timelockSafe, params.timelock, callCount, bytes32(0));
        report.timelockBatch = timelockReport.timelockBatch;
        report.timelockDelay = timelockReport.timelockDelay;
        report.predecessor = timelockReport.predecessor;

        uint256 callIndex = ERPMarketOffboarding.appendRecoveryIntegrationRemovalCalls(
            markets, integrations, params.liquidationPeriphery, params.marketRegistry, false, report.timelockBatch, 0
        );
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
            require(!ERPMarketOffboarding.hasDebt(markets[i].market), "Batch C: market debt remains");
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

            ERPMarketOffboarding.validateFrozenAndNotPaused(address(market), "Batch C");
            ERPMarketOffboarding.validateRecoveryExitRoutes(address(market), params.altoAdapter);
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

    function _fixedRateMarkets(BorrowMarketOffboardingMarket[] memory markets)
        private
        pure
        returns (ERPMarketOffboarding.FixedRateMarket[] memory configured)
    {
        configured = new ERPMarketOffboarding.FixedRateMarket[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            configured[i] = ERPMarketOffboarding.FixedRateMarket(markets[i].market, markets[i].fixedRateSpy);
        }
    }

    function _recoveryMarkets(BorrowMarketOffboardingMarket[] memory markets)
        private
        pure
        returns (ERPMarketOffboarding.RecoveryMarket[] memory configured)
    {
        configured = new ERPMarketOffboarding.RecoveryMarket[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            configured[i] = ERPMarketOffboarding.RecoveryMarket(markets[i].market, markets[i].leverage);
        }
    }

    function _newTimelockReport(address safe, address timelock, uint256 callCount, bytes32 predecessor)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        (report.timelockBatch, report.timelockDelay) = ERPMarketOffboarding.newTimelockBatch(safe, timelock, callCount);
        report.predecessor = predecessor;
    }

    function _requireNonZero(address value, string memory errorMessage) private pure {
        require(value != address(0), errorMessage);
    }
}
