// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    BatchBReduceLtvParams,
    BatchBSetFixedRateIrmParams,
    BatchCRecoverParams,
    MintMarketOffboardingContracts,
    MintMarketOffboardingInput,
    MintMarketOffboardingManifest,
    MintMarketOffboardingMarket,
    MintMarketOffboardingPhase,
    MintMarketOffboardingReport,
    MintMarketOffboardingSchedulePhase,
    MintMarketOffboardingSimulationTotals,
    MintMarketOffboardingSeverity
} from "./IMintMarketOffboarding.sol";

import {ERPOutputWriter, ERPTransactionBatch} from "../libraries/ERPOutputWriter.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Builds and writes operational phases for ERP-OFFBOARD-01.
library MintMarketOffboarding {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant MAX_LTV_REDUCTION = 0.05 ether;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant MAX_BORROW_RATE_SPY = 8 ether / YEAR;
    uint256 internal constant TERMINAL_STEP_INTERVAL = 1 hours;
    string internal constant ERP_OUTPUT_DIR = "ERP/ERP-OFFBOARD-01/output";

    struct RecoveryIntegrationState {
        address leverageSwapper;
        bool leverageSupported;
        bool callbackAuthorized;
        bool swapperWhitelisted;
        bool liquidationSupported;
        bool liquidationAuthorized;
        bool registered;
    }

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
            report = _prepareRecoveryPhase(manifest, contracts);
        } else {
            revert("ERP: invalid phase");
        }

        _writePhaseArtifacts(phase, manifest, input, report);
        return input;
    }

    function _prepareFixedRateIrmPhase(
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input
    ) private returns (MintMarketOffboardingReport memory) {
        address factory = input.contracts.ownerFixedRateIrmFactory;
        if (factory == address(0)) {
            factory = _deployOwnerFixedRateIrmFactory(input.contracts.timelock);
            input.contracts.ownerFixedRateIrmFactory = factory;
        }

        return _prepareFixedRateIrmAttachment(
            BatchBSetFixedRateIrmParams({
                timelockSafe: manifest.timelockSafe,
                timelock: input.contracts.timelock,
                ownerFixedRateIrmFactory: factory,
                version: manifest.fixedRateIrmVersion,
                markets: manifest.markets
            })
        );
    }

    function _prepareRecoveryPhase(
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingContracts memory contracts
    ) private view returns (MintMarketOffboardingReport memory) {
        return _prepareRecovery(
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
        require(
            totals.liquidationFundingAssets <= market.maxLiquidationFundingAssets, "Simulation: funding limit exceeded"
        );
        require(totals.badDebtAssets <= market.maxBadDebtAssets, "Simulation: bad debt limit exceeded");
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
        uint256 freezerCallCount;
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

            if (!IMarketBase(marketAddress).paused(FROZEN_TYPE)) ++freezerCallCount;
        }

        report = _newTimelockReport(
            manifest.timelockSafe, input.contracts.timelock, manifest.markets.length * 4, bytes32(0)
        );
        report.freezerBatch = ERPOutputWriter.newBatch(manifest.freezerSafe, freezerCallCount);
        uint256 freezerCallIndex;
        for (uint256 i; i < manifest.markets.length; ++i) {
            address marketAddress = manifest.markets[i].market;
            if (IMarketBase(marketAddress).paused(FROZEN_TYPE)) continue;
            freezerCallIndex = ERPOutputWriter.addBatchCall(
                report.freezerBatch,
                freezerCallIndex,
                marketAddress,
                abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true))
            );
        }
        assert(freezerCallIndex == freezerCallCount);

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

    function _deployOwnerFixedRateIrmFactory(address timelock) private returns (address) {
        require(timelock != address(0), "Factory deploy: invalid Timelock");

        OwnerFixedRateIrmFactory factory = new OwnerFixedRateIrmFactory(timelock);

        console2.log("OwnerFixedRateIrmFactory:", address(factory));
        console2.log("Owner:", timelock);
        console2.log("Manual update required in addresses.json: .contracts.ownerFixedRateIrmFactory");

        return address(factory);
    }

    function _prepareFixedRateIrmAttachment(BatchBSetFixedRateIrmParams memory params)
        private
        view
        returns (MintMarketOffboardingReport memory report)
    {
        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(params.ownerFixedRateIrmFactory);
        uint256 marketCount = params.markets.length;
        report = _newTimelockReport(params.timelockSafe, params.timelock, marketCount * 2, bytes32(0));

        for (uint256 i; i < marketCount; ++i) {
            address market = params.markets[i].market;
            uint256 fixedRateSpy = params.markets[i].fixedRateSpy;
            Balance memory totalBorrowed = IMarket(market).totalBorrowed();

            _validateFrozenAndNotPaused(market, "Batch B");
            require(totalBorrowed.assets != 0 || totalBorrowed.shares != 0, "Batch B: debt targets reached");
            require(fixedRateSpy <= MAX_BORROW_RATE_SPY, "Batch B: rate above IRM maximum");

            address predictedIrm = factory.predictIrmAddress(market, params.version, fixedRateSpy);
            ERPOutputWriter.addBatchCall(
                report.timelockBatch,
                i,
                address(factory),
                abi.encodeCall(OwnerFixedRateIrmFactory.deploy, (market, params.version, fixedRateSpy))
            );
            ERPOutputWriter.addBatchCall(
                report.timelockBatch, marketCount + i, market, abi.encodeCall(IMarketBase.setIrm, (predictedIrm, false))
            );
        }
    }

    function _prepareRateAndLtvReduction(BatchBReduceLtvParams memory params)
        private
        view
        returns (MintMarketOffboardingReport memory report)
    {
        uint256 marketCount = _debtBearingMarketCount(params.markets);
        require(marketCount != 0, "Batch B: debt targets reached");

        report = _newTimelockReport(params.timelockSafe, params.timelock, marketCount * 5, params.lastOperationId);

        uint256 callIndex;
        for (uint256 i; i < params.markets.length; ++i) {
            MintMarketOffboardingMarket memory configuredMarket = params.markets[i];
            if (!_hasDebt(configuredMarket.market)) continue;
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
        _validateFrozenAndNotPaused(address(market), "Batch B");
        require(configuredMarket.ltvReduction <= MAX_LTV_REDUCTION, "Batch B: LTV reduction above maximum");

        address fixedRateIrm = market.irm();
        address liquidationEngine = market.liquidationEngine();
        _validateRateCorrection(
            params, address(market), fixedRateIrm, liquidationEngine, configuredMarket.correctionRateSpy
        );
        _validateMintCorrectionState(configuredMarket, market, IDUSD(params.dusd));

        (uint256 reducedMarketMaxLtv, LiquidationConfiguration memory liquidationConfiguration) =
            _reducedLtvConfiguration(market, liquidationEngine, configuredMarket.ltvReduction);

        callIndex = ERPOutputWriter.addBatchCall(
            batch,
            callIndex,
            fixedRateIrm,
            abi.encodeCall(FixedRateIrm.setBorrowRate, (configuredMarket.correctionRateSpy))
        );
        callIndex = ERPOutputWriter.addBatchCall(
            batch, callIndex, address(market), abi.encodeCall(AltoMintMarket.claimInterest, (0))
        );
        callIndex = ERPOutputWriter.addBatchCall(
            batch, callIndex, address(market), abi.encodeCall(IMarketBase.setMaxLtv, (reducedMarketMaxLtv))
        );
        callIndex = ERPOutputWriter.addBatchCall(
            batch,
            callIndex,
            liquidationEngine,
            abi.encodeCall(IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (liquidationConfiguration))
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

    function _validateRateCorrection(
        BatchBReduceLtvParams memory params,
        address market,
        address fixedRateIrm,
        address liquidationEngine,
        uint256 borrowRateSpy
    ) private view {
        require(IIrm(fixedRateIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Batch B: IRM is not fixed-rate");
        require(FixedRateIrm(fixedRateIrm).market() == market, "Batch B: IRM not dedicated");
        require(
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).market() == market, "Batch B: wrong liquidation engine"
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
        reducedMarketMaxLtv = _saturatingSub(market.maxLtv(), ltvReduction);
        configuration.maxLiquidationLtv = _saturatingSub(configuration.maxLiquidationLtv, ltvReduction);
        configuration.ltvForCompleteLiquidation = _saturatingSub(configuration.ltvForCompleteLiquidation, ltvReduction);
        require(
            reducedMarketMaxLtv <= configuration.maxLiquidationLtv
                && configuration.maxLiquidationLtv <= configuration.ltvForCompleteLiquidation,
            "Batch B: invalid LTV order"
        );
    }

    function _validateCorrectionSchedule(MintMarketOffboardingManifest memory manifest, address timelock)
        private
        view
        returns (uint256 aprFloorSpy, uint256 previousAprFloorSpy)
    {
        require(manifest.t0 <= block.timestamp, "Batch B: T0 is in the future");
        require(manifest.lastExecutedStep + 1 == manifest.step, "Batch B: steps must be sequential");

        if (manifest.schedulePhase == MintMarketOffboardingSchedulePhase.SCHEDULED) {
            (uint256 offset, uint256 aprFloor) = _scheduledStep(manifest.severity, manifest.step);
            require(block.timestamp >= manifest.t0 + offset, "Batch B: scheduled step is not due");

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
        } else if (manifest.schedulePhase == MintMarketOffboardingSchedulePhase.TERMINAL) {
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
            require(_debtBearingMarketCount(manifest.markets) != 0, "Batch B: debt targets reached");
            _validatePriorOperationExecuted(timelock, manifest.lastOperationId);

            uint256 terminalAprFloor = _terminalAprFloor(manifest.severity);
            aprFloorSpy = _aprToSpy(terminalAprFloor);
            previousAprFloorSpy = aprFloorSpy;
        } else {
            revert("Batch B: invalid schedule phase");
        }
    }

    function _scheduledStep(MintMarketOffboardingSeverity severity, uint256 step)
        private
        pure
        returns (uint256 offset, uint256 aprFloor)
    {
        if (severity == MintMarketOffboardingSeverity.MEDIUM) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (7 days, 0.2 ether);
            if (step == 3) return (14 days, 0.4 ether);
            if (step == 4) return (21 days, 0.8 ether);
        } else if (severity == MintMarketOffboardingSeverity.HIGH) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (4 days, 0.2 ether);
            if (step == 3) return (7 days, 0.4 ether);
            if (step == 4) return (10 days, 0.8 ether);
        } else if (severity == MintMarketOffboardingSeverity.CRITICAL) {
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

    function _terminalOffset(MintMarketOffboardingSeverity severity) private pure returns (uint256) {
        if (severity == MintMarketOffboardingSeverity.MEDIUM) return 28 days;
        if (severity == MintMarketOffboardingSeverity.HIGH) return 14 days;
        if (severity == MintMarketOffboardingSeverity.CRITICAL) return 7 days;
        revert("Batch B: invalid severity");
    }

    function _terminalAprFloor(MintMarketOffboardingSeverity severity) private pure returns (uint256) {
        return severity == MintMarketOffboardingSeverity.CRITICAL ? 3.2 ether : 0.8 ether;
    }

    function _aprToSpy(uint256 apr) private pure returns (uint256) {
        return apr / YEAR;
    }

    function _debtBearingMarketCount(MintMarketOffboardingMarket[] memory markets)
        private
        view
        returns (uint256 count)
    {
        for (uint256 i; i < markets.length; ++i) {
            if (_hasDebt(markets[i].market)) ++count;
        }
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

    function _validateFrozenAndNotPaused(address market, string memory batchName) private view {
        require(IMarketBase(market).paused(FROZEN_TYPE), string.concat(batchName, ": market not frozen"));
        require(!IMarketBase(market).paused(PAUSE_TYPE), string.concat(batchName, ": market paused"));
    }

    function _prepareRecovery(BatchCRecoverParams memory params)
        private
        view
        returns (MintMarketOffboardingReport memory report)
    {
        _validateRecoveryState(params);

        (RecoveryIntegrationState[] memory integrations, uint256 integrationCallCount) =
            _loadRecoveryIntegrationStates(params);
        uint256 callCount = params.markets.length * 4 + integrationCallCount;
        report = _newTimelockReport(params.timelockSafe, params.timelock, callCount, bytes32(0));

        uint256 callIndex = _appendMintShutdownCalls(params, report.timelockBatch, 0);
        callIndex = _appendLeverageRemovalCalls(params, integrations, report.timelockBatch, callIndex);
        callIndex = _appendLiquidationRemovalCalls(params, integrations, report.timelockBatch, callIndex);
        callIndex = _appendRegistryRemovalCalls(params, integrations, report.timelockBatch, callIndex);
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
            _validateFrozenAndNotPaused(marketAddress, "Batch C");
            require(market.oracle() != address(0), "Batch C: market oracle unavailable");
            require(
                AdapterContractApproval(params.altoAdapter).isApprovedContract(marketAddress),
                "Batch C: adapter route unavailable"
            );
        }
    }

    function _loadRecoveryIntegrationStates(BatchCRecoverParams memory params)
        private
        view
        returns (RecoveryIntegrationState[] memory integrations, uint256 callCount)
    {
        integrations = new RecoveryIntegrationState[](params.markets.length);
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            AltoLeverage leverage = AltoLeverage(params.markets[i].leverage);
            IAltoLeverageSwapper leverageSwapper = leverage.swapper();
            RecoveryIntegrationState memory integration = RecoveryIntegrationState({
                leverageSwapper: address(leverageSwapper),
                leverageSupported: leverage.supportedMarkets(market),
                callbackAuthorized: IMarket(market).authorizedCallbacks(address(leverage)),
                swapperWhitelisted: leverageSwapper.isWhitelisted(address(leverage)),
                liquidationSupported: ILiquidationPeripheryBase(params.liquidationPeriphery).supportedMarkets(market),
                liquidationAuthorized: IMarket(market).authorizedLiquidationPeriphery(params.liquidationPeriphery),
                registered: IMarketRegistry(params.marketRegistry).isMintMarket(market)
            });
            integrations[i] = integration;

            if (integration.leverageSupported) ++callCount;
            if (integration.callbackAuthorized) ++callCount;
            if (integration.swapperWhitelisted) ++callCount;
            if (integration.liquidationSupported) ++callCount;
            if (integration.liquidationAuthorized) ++callCount;
            if (integration.registered) ++callCount;
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

    function _appendLeverageRemovalCalls(
        BatchCRecoverParams memory params,
        RecoveryIntegrationState[] memory integrations,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private pure returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            AltoLeverage leverage = AltoLeverage(params.markets[i].leverage);
            RecoveryIntegrationState memory integration = integrations[i];

            if (integration.leverageSupported) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch, callIndex, address(leverage), abi.encodeCall(AltoLeverage.setMarket, (market, false))
                );
            }
            if (integration.callbackAuthorized) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    market,
                    abi.encodeCall(IMarketBase.setAuthorizedCallback, (address(leverage), false))
                );
            }

            if (integration.swapperWhitelisted) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    integration.leverageSwapper,
                    abi.encodeCall(IAltoLeverageSwapper.setWhitelisted, (address(leverage), false))
                );
            }
        }
        return callIndex;
    }

    function _appendLiquidationRemovalCalls(
        BatchCRecoverParams memory params,
        RecoveryIntegrationState[] memory integrations,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private pure returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            RecoveryIntegrationState memory integration = integrations[i];
            if (integration.liquidationSupported) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    params.liquidationPeriphery,
                    abi.encodeCall(ILiquidationPeripheryBase.setSupportedMarket, (market, false))
                );
            }
            if (integration.liquidationAuthorized) {
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
        RecoveryIntegrationState[] memory integrations,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) private pure returns (uint256) {
        for (uint256 i; i < params.markets.length; ++i) {
            address market = params.markets[i].market;
            if (!integrations[i].registered) continue;

            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, params.marketRegistry, abi.encodeCall(IMarketRegistry.removeMintMarket, (market))
            );
        }
        return callIndex;
    }

    function _newTimelockReport(address safe, address timelock, uint256 callCount, bytes32 predecessor)
        private
        view
        returns (MintMarketOffboardingReport memory report)
    {
        report.timelockBatch = ERPOutputWriter.newBatch(safe, callCount);
        report.timelockDelay = TimelockController(payable(timelock)).getMinDelay();
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
        string memory outputDirectory = string.concat(ERP_OUTPUT_DIR, "/", manifest.activationId);
        if (
            phase == MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM
                || phase == MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV
        ) {
            outputDirectory = string.concat(
                outputDirectory, "/severity-", _severityName(manifest.severity), "/step-", vm.toString(manifest.step)
            );
        }
        return string.concat(outputDirectory, "/source-block-", vm.toString(manifest.sourceBlock));
    }

    function _severityName(MintMarketOffboardingSeverity severity) private pure returns (string memory) {
        if (severity == MintMarketOffboardingSeverity.MEDIUM) return "medium";
        if (severity == MintMarketOffboardingSeverity.HIGH) return "high";
        if (severity == MintMarketOffboardingSeverity.CRITICAL) return "critical";
        revert("ERP: invalid severity");
    }
}
