// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    BatchBReduceLtvParams,
    BatchCRecoverParams,
    MintMarketOffboardingContracts,
    MintMarketOffboardingInput,
    MintMarketOffboardingManifest,
    MintMarketOffboardingMarket,
    MintMarketOffboardingPhase,
    MintMarketOffboardingReport,
    MintMarketOffboardingSimulationTotals
} from "./IMintMarketOffboarding.sol";

import {ERPOutputWriter, ERPTransactionBatch} from "../libraries/ERPOutputWriter.sol";
import {ERPMarketOffboarding} from "../libraries/ERPMarketOffboarding.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Builds and writes operational phases for ERP-OFFBOARD-01.
library MintMarketOffboarding {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant ERP_OUTPUT_DIR = "ERP/ERP-OFFBOARD-01/output";

    struct TimelockArtifactMetadata {
        string fileStem;
        string name;
        bool optional;
    }

    function runPhase(
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input
    ) internal returns (MintMarketOffboardingInput memory) {
        MintMarketOffboardingContracts memory contracts = input.contracts;
        MintMarketOffboardingReport memory report;

        if (phase == MintMarketOffboardingPhase.BATCH_A_CONTAIN) {
            report = _prepareContainment(manifest, input);
        } else if (phase == MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM) {
            report = _prepareFixedRateIrmPhase(manifest, input);
        } else if (phase == MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            report = _prepareRateAndLtvReduction(manifest, input);
        } else if (phase == MintMarketOffboardingPhase.BATCH_C_RECOVER) {
            report = _prepareRecovery(
                BatchCRecoverParams({
                    timelockSafe: manifest.timelockSafe,
                    timelock: contracts.timelock,
                    dusd: contracts.dusd,
                    marketRegistry: contracts.marketRegistry,
                    altoAdapter: contracts.altoAdapter,
                    liquidationPeriphery: contracts.liquidationPeriphery,
                    markets: manifest.markets
                })
            );
        } else {
            revert("ERP: invalid phase");
        }

        _writePhaseArtifacts(phase, manifest, input, report);
        return input;
    }

    function _prepareFixedRateIrmPhase(
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input
    ) private returns (MintMarketOffboardingReport memory report) {
        address factory = input.contracts.ownerFixedRateIrmFactory;
        if (factory == address(0)) {
            factory = ERPMarketOffboarding.deployOwnerFixedRateIrmFactory(input.contracts.timelock);
            input.contracts.ownerFixedRateIrmFactory = factory;
        }

        (report.timelockBatch, report.timelockDelay) = ERPMarketOffboarding.buildFixedRateBatch(
            manifest.timelockSafe,
            input.contracts.timelock,
            factory,
            manifest.fixedRateIrmVersion,
            _fixedRateMarkets(manifest.markets)
        );
    }

    /// @notice Builds the exact Batch B rate, fee, LTV and debt-ceiling calls without writing artifacts.
    function _prepareRateAndLtvReduction(
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input
    ) internal view returns (MintMarketOffboardingReport memory report) {
        (uint256 aprFloorSpy, uint256 previousAprFloorSpy) =
            _validateCorrectionSchedule(manifest, input.contracts.timelock);
        report = _prepareRateAndLtvReduction(
            BatchBReduceLtvParams({
                timelockSafe: manifest.timelockSafe,
                timelock: input.contracts.timelock,
                dusd: input.contracts.dusd,
                aprFloorSpy: aprFloorSpy,
                previousAprFloorSpy: previousAprFloorSpy,
                lastStepExecutedAt: manifest.lastStepExecutedAt,
                lastOperationId: manifest.lastOperationId,
                markets: manifest.markets
            })
        );
    }

    /// @notice Rejects a simulated Mint Market outcome outside governance-approved limits.
    function _validateSimulationLimits(
        MintMarketOffboardingSimulationTotals memory totals,
        MintMarketOffboardingMarket memory market
    ) internal pure {
        ERPMarketOffboarding.validateCommonSimulationLimits(
            totals.liquidationFundingAssets,
            totals.badDebtAssets,
            market.maxLiquidationFundingAssets,
            market.maxBadDebtAssets
        );
        require(
            totals.seizedCollateralAssets <= market.maxSeizedCollateralAssets,
            "Simulation: seized collateral limit exceeded"
        );
    }

    function _prepareContainment(MintMarketOffboardingManifest memory manifest, MintMarketOffboardingInput memory input)
        internal
        view
        returns (MintMarketOffboardingReport memory report)
    {
        IDUSD dusd = IDUSD(input.contracts.dusd);
        for (uint256 i; i < manifest.markets.length; ++i) {
            MintMarketOffboardingMarket memory configuredMarket = manifest.markets[i];
            address marketAddress = configuredMarket.market;
            IMarket market = IMarket(marketAddress);
            Balance memory totalBorrowed = market.totalBorrowed();
            Balance memory totalSupply = market.totalSupply();
            uint256 badDebt = AltoMintMarket(marketAddress).badDebtAssets();
            uint256 claimableFees = AltoMintMarket(marketAddress).claimableFeesAssets();
            (uint256 minted, uint256 currentMinterCeiling) = dusd.minterConfig(marketAddress);

            require(!market.paused(PAUSE_TYPE), "Batch A: market paused");
            require(configuredMarket.debtCeiling <= totalSupply.assets, "Batch A: debt ceiling increase");
            require(
                configuredMarket.debtCeiling >= totalBorrowed.assets + badDebt,
                "Batch A: debt ceiling below current exposure"
            );
            require(configuredMarket.dusdMinterCeiling <= currentMinterCeiling, "Batch A: DUSD minter ceiling increase");
            require(
                configuredMarket.dusdMinterCeiling >= minted + claimableFees, "Batch A: DUSD ceiling below current fees"
            );
        }

        report = _newTimelockReport(
            manifest.timelockSafe, input.contracts.timelock, manifest.markets.length * 4, bytes32(0)
        );
        report.freezerBatch =
            ERPMarketOffboarding.buildFreezeBatch(manifest.freezerSafe, _marketAddresses(manifest.markets));

        uint256 timelockCallCount = report.timelockBatch.targets.length;
        uint256 timelockCallIndex;
        for (uint256 i; i < manifest.markets.length; ++i) {
            MintMarketOffboardingMarket memory configuredMarket = manifest.markets[i];

            timelockCallIndex = ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                timelockCallIndex,
                configuredMarket.market,
                abi.encodeCall(IMarketBase.accrueInterest, ())
            );
            timelockCallIndex = ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                timelockCallIndex,
                configuredMarket.market,
                abi.encodeCall(AltoMintMarket.claimInterest, (0))
            );
            timelockCallIndex = ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                timelockCallIndex,
                configuredMarket.market,
                abi.encodeCall(AltoMintMarket.setDebtCeiling, (configuredMarket.debtCeiling))
            );
            timelockCallIndex = ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                timelockCallIndex,
                input.contracts.dusd,
                abi.encodeCall(IDUSD.setMinterCeiling, (configuredMarket.market, configuredMarket.dusdMinterCeiling))
            );
        }
        assert(timelockCallIndex == timelockCallCount);
    }

    function _prepareRateAndLtvReduction(BatchBReduceLtvParams memory params)
        private
        view
        returns (MintMarketOffboardingReport memory report)
    {
        uint256 marketCount = ERPMarketOffboarding.debtBearingMarketCount(_marketAddresses(params.markets));
        require(marketCount != 0, "Batch B: debt targets reached");

        report = _newTimelockReport(params.timelockSafe, params.timelock, marketCount * 5, params.lastOperationId);

        uint256 callIndex;
        for (uint256 i; i < params.markets.length; ++i) {
            MintMarketOffboardingMarket memory configuredMarket = params.markets[i];
            if (!ERPMarketOffboarding.hasDebt(configuredMarket.market)) continue;
            callIndex = _appendRateAndLtvReductionCalls(report.timelockBatch, callIndex, params, configuredMarket);
        }
        assert(callIndex == marketCount * 5);
    }

    function _appendRateAndLtvReductionCalls(
        ERPTransactionBatch memory batch,
        uint256 callIndex,
        BatchBReduceLtvParams memory params,
        MintMarketOffboardingMarket memory configuredMarket
    ) private view returns (uint256) {
        IMarket market = IMarket(configuredMarket.market);
        ERPMarketOffboarding.validateFrozenAndNotPaused(address(market), "Batch B");
        ERPMarketOffboarding.validateLtvReduction(configuredMarket.ltvReduction);

        address fixedRateIrm = market.irm();
        address liquidationEngine = market.liquidationEngine();
        ERPMarketOffboarding.validateRateCorrection(
            address(market),
            fixedRateIrm,
            liquidationEngine,
            configuredMarket.correctionRateSpy,
            params.aprFloorSpy,
            params.previousAprFloorSpy,
            params.lastStepExecutedAt
        );
        _validateMintCorrectionState(configuredMarket, market, IDUSD(params.dusd));

        (uint256 reducedMarketMaxLtv, LiquidationConfiguration memory liquidationConfiguration) = ERPMarketOffboarding.reducedLtvConfiguration(
            address(market), liquidationEngine, configuredMarket.ltvReduction
        );

        callIndex = ERPMarketOffboarding.appendRateUpdateCall(
            batch, callIndex, fixedRateIrm, configuredMarket.correctionRateSpy
        );
        callIndex = ERPOutputWriter.addBatchCall(
            batch, callIndex, address(market), abi.encodeCall(AltoMintMarket.claimInterest, (0))
        );
        callIndex = ERPMarketOffboarding.appendLtvUpdateCalls(
            batch, callIndex, address(market), liquidationEngine, reducedMarketMaxLtv, liquidationConfiguration
        );
        return ERPOutputWriter.addBatchCall(
            batch,
            callIndex,
            address(market),
            abi.encodeCall(AltoMintMarket.setDebtCeiling, (configuredMarket.debtCeiling))
        );
    }

    function _validateMintCorrectionState(
        MintMarketOffboardingMarket memory configuredMarket,
        IMarket market,
        IDUSD dusd
    ) private view {
        Balance memory totalBorrowed = market.totalBorrowed();
        Balance memory totalSupply = market.totalSupply();
        uint256 badDebtAssets = AltoMintMarket(address(market)).badDebtAssets();
        uint256 claimableFeesAssets = AltoMintMarket(address(market)).claimableFeesAssets();
        require(claimableFeesAssets <= configuredMarket.maxDusdMintedAssets, "Batch B: DUSD mint limit exceeded");
        (uint256 minted, uint256 minterCeiling) = dusd.minterConfig(address(market));
        require(minted + claimableFeesAssets <= minterCeiling, "Batch B: insufficient DUSD mint capacity");
        require(configuredMarket.debtCeiling <= totalSupply.assets, "Batch B: debt ceiling increase");
        require(
            configuredMarket.debtCeiling >= totalBorrowed.assets + badDebtAssets,
            "Batch B: debt ceiling below current exposure"
        );
    }

    function _validateCorrectionSchedule(MintMarketOffboardingManifest memory manifest, address timelock)
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
        returns (MintMarketOffboardingReport memory report)
    {
        _validateRecoveryState(params);

        ERPMarketOffboarding.RecoveryMarket[] memory markets = _recoveryMarkets(params.markets);
        (ERPMarketOffboarding.RecoveryIntegrationState[] memory integrations, uint256 integrationCallCount) = ERPMarketOffboarding.loadRecoveryIntegrationStates(
            markets, params.liquidationPeriphery, params.marketRegistry, true
        );
        uint256 callCount = params.markets.length * 4 + integrationCallCount;
        report = _newTimelockReport(params.timelockSafe, params.timelock, callCount, bytes32(0));

        uint256 callIndex = _appendMintShutdownCalls(params, report.timelockBatch, 0);
        callIndex = ERPMarketOffboarding.appendRecoveryIntegrationRemovalCalls(
            markets,
            integrations,
            params.liquidationPeriphery,
            params.marketRegistry,
            true,
            report.timelockBatch,
            callIndex
        );
        assert(callIndex == callCount);
    }

    function _validateRecoveryState(BatchCRecoverParams memory params) private view {
        IDUSD dusd = IDUSD(params.dusd);
        for (uint256 i; i < params.markets.length; ++i) {
            address marketAddress = params.markets[i].market;
            IMarket market = IMarket(marketAddress);
            Balance memory borrowed = market.totalBorrowed();
            (uint256 minted,) = dusd.minterConfig(marketAddress);

            uint256 badDebtAssets = AltoMintMarket(marketAddress).badDebtAssets();

            require(borrowed.assets == 0 && borrowed.shares == 0, "Batch C: market debt remains");
            require(
                badDebtAssets == params.markets[i].approvedRecoveryBadDebtAssets,
                "Batch C: bad debt does not match approved residual"
            );
            require(AltoMintMarket(marketAddress).claimableFeesAssets() == 0, "Batch C: claimable fees remain");
            require(minted <= params.markets[i].maxUnbackedDusdAssets, "Batch C: unbacked DUSD exceeds approved limit");
            ERPMarketOffboarding.validateFrozenAndNotPaused(marketAddress, "Batch C");
            ERPMarketOffboarding.validateRecoveryExitRoutes(marketAddress, params.altoAdapter);
        }
    }

    function _appendMintShutdownCalls(
        BatchCRecoverParams memory params,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private view returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            uint256 badDebtAssets = AltoMintMarket(market).badDebtAssets();
            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, market, abi.encodeCall(AltoMintMarket.setDebtCeiling, (badDebtAssets))
            );
            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, params.dusd, abi.encodeCall(IDUSD.setMinterCeiling, (market, 0))
            );
            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, params.dusd, abi.encodeCall(IDUSD.setMinterStatus, (market, false))
            );
            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, params.dusd, abi.encodeCall(IDUSD.setBurnerStatus, (market, false))
            );
        }
        return callIndex;
    }

    function _newTimelockReport(address safe, address timelock, uint256 callCount, bytes32 predecessor)
        private
        view
        returns (MintMarketOffboardingReport memory report)
    {
        (report.timelockBatch, report.timelockDelay) = ERPMarketOffboarding.newTimelockBatch(safe, timelock, callCount);
        report.predecessor = predecessor;
    }

    function _writePhaseArtifacts(
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input,
        MintMarketOffboardingReport memory report
    ) private {
        string memory outputDirectory = artifactDirectory(phase, manifest);
        vm.createDir(outputDirectory, true);

        if (phase == MintMarketOffboardingPhase.BATCH_A_CONTAIN) {
            ERPOutputWriter.writeOptionalSafeBatch(
                outputDirectory,
                "batch-a-freeze-safe.json",
                "ERP-OFFBOARD-01 - Batch A Freeze Mint Markets",
                report.freezerBatch
            );
        }

        TimelockArtifactMetadata memory metadata = _timelockArtifactMetadata(phase);
        if (metadata.optional) {
            ERPOutputWriter.writeOptionalTimelockPair(
                outputDirectory,
                metadata.fileStem,
                metadata.name,
                input.contracts.timelock,
                report.timelockBatch,
                report.timelockDelay,
                report.predecessor
            );
        } else {
            ERPOutputWriter.writeTimelockPair(
                outputDirectory,
                metadata.fileStem,
                metadata.name,
                input.contracts.timelock,
                report.timelockBatch,
                report.timelockDelay,
                report.predecessor
            );
        }
    }

    function _timelockArtifactMetadata(MintMarketOffboardingPhase phase)
        private
        pure
        returns (TimelockArtifactMetadata memory metadata)
    {
        if (phase == MintMarketOffboardingPhase.BATCH_A_CONTAIN) {
            metadata.fileStem = "batch-a-containment";
            metadata.name = "ERP-OFFBOARD-01 - Batch A Claim Fees and Constrain Mint Markets";
        } else if (phase == MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM) {
            metadata.fileStem = "batch-b-fixed-rate-irm";
            metadata.name = "ERP-OFFBOARD-01 - Batch B Deploy and Attach Fixed-Rate IRMs";
        } else if (phase == MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            metadata.fileStem = "batch-b-irm-and-ltv-update";
            metadata.name = "ERP-OFFBOARD-01 - Batch B Update IRM, Fees, LTVs and Debt Ceiling";
        } else if (phase == MintMarketOffboardingPhase.BATCH_C_RECOVER) {
            metadata.fileStem = "batch-c-final-removal";
            metadata.name = "ERP-OFFBOARD-01 - Batch C Final Mint Market Removal";
            metadata.optional = true;
        } else {
            revert("ERP: invalid phase");
        }
    }

    function artifactDirectory(MintMarketOffboardingPhase phase, MintMarketOffboardingManifest memory manifest)
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

    function _marketAddresses(MintMarketOffboardingMarket[] memory markets)
        private
        pure
        returns (address[] memory addresses)
    {
        addresses = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            addresses[i] = markets[i].market;
        }
    }

    function _fixedRateMarkets(MintMarketOffboardingMarket[] memory markets)
        private
        pure
        returns (ERPMarketOffboarding.FixedRateMarket[] memory configured)
    {
        configured = new ERPMarketOffboarding.FixedRateMarket[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            configured[i] = ERPMarketOffboarding.FixedRateMarket(markets[i].market, markets[i].fixedRateSpy);
        }
    }

    function _recoveryMarkets(MintMarketOffboardingMarket[] memory markets)
        private
        pure
        returns (ERPMarketOffboarding.RecoveryMarket[] memory configured)
    {
        configured = new ERPMarketOffboarding.RecoveryMarket[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            configured[i] = ERPMarketOffboarding.RecoveryMarket(markets[i].market, markets[i].leverage);
        }
    }
}
