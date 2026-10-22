// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERPOutputWriter, ERPTransactionBatch} from "./ERPOutputWriter.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
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
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Policy-neutral mechanics shared by the Mint and Borrow Market offboarding ERPs.
library ERPMarketOffboarding {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant MAX_LTV_REDUCTION = 0.05 ether;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant MAX_BORROW_RATE_SPY = 8 ether / YEAR;
    uint256 internal constant TERMINAL_STEP_INTERVAL = 1 hours;

    uint8 internal constant PHASE_SET_FIXED_RATE_IRM = 1;
    uint8 internal constant PHASE_REDUCE_LTV = 2;
    uint8 internal constant SCHEDULED = 0;
    uint8 internal constant TERMINAL = 1;
    uint8 internal constant MEDIUM = 0;
    uint8 internal constant HIGH = 1;
    uint8 internal constant CRITICAL = 2;

    struct ScheduleParams {
        uint8 severity;
        uint8 schedulePhase;
        uint256 t0;
        uint256 step;
        uint256 lastExecutedStep;
        uint256 lastStepExecutedAt;
        bytes32 lastOperationId;
    }

    struct FixedRateMarket {
        address market;
        uint256 fixedRateSpy;
    }

    struct RecoveryMarket {
        address market;
        address leverage;
    }

    struct RecoveryIntegrationState {
        address leverageSwapper;
        bool leverageSupported;
        bool callbackAuthorized;
        bool swapperWhitelisted;
        bool liquidationSupported;
        bool liquidationAuthorized;
        bool registered;
    }

    function deployOwnerFixedRateIrmFactory(address timelock) internal returns (address) {
        require(timelock != address(0), "Factory deploy: invalid Timelock");
        OwnerFixedRateIrmFactory factory = new OwnerFixedRateIrmFactory(timelock);
        console2.log("OwnerFixedRateIrmFactory:", address(factory));
        console2.log("Owner:", timelock);
        console2.log("Manual update required in addresses.json: .contracts.ownerFixedRateIrmFactory");
        return address(factory);
    }

    function newTimelockBatch(address safe, address timelock, uint256 callCount)
        internal
        view
        returns (ERPTransactionBatch memory batch, uint256 delay)
    {
        batch = ERPOutputWriter.newBatch(safe, callCount);
        delay = TimelockController(payable(timelock)).getMinDelay();
    }

    function artifactDirectory(
        string memory root,
        string memory activationId,
        uint8 phase,
        uint8 severity,
        uint256 step,
        uint256 sourceBlock
    ) internal pure returns (string memory) {
        string memory directory = string.concat(root, "/", activationId);
        if (phase == PHASE_SET_FIXED_RATE_IRM || phase == PHASE_REDUCE_LTV) {
            directory = string.concat(directory, "/severity-", severityName(severity), "/step-", VM.toString(step));
        }
        return string.concat(directory, "/source-block-", VM.toString(sourceBlock));
    }

    function severityName(uint8 severity) internal pure returns (string memory) {
        if (severity == MEDIUM) return "medium";
        if (severity == HIGH) return "high";
        if (severity == CRITICAL) return "critical";
        revert("ERP: invalid severity");
    }

    function buildFreezeBatch(address safe, address[] memory markets)
        internal
        view
        returns (ERPTransactionBatch memory batch)
    {
        uint256 callCount;
        for (uint256 i; i < markets.length; ++i) {
            if (!IMarketBase(markets[i]).paused(FROZEN_TYPE)) ++callCount;
        }
        batch = ERPOutputWriter.newBatch(safe, callCount);
        uint256 callIndex;
        for (uint256 i; i < markets.length; ++i) {
            if (IMarketBase(markets[i]).paused(FROZEN_TYPE)) continue;
            callIndex = ERPOutputWriter.addBatchCall(
                batch, callIndex, markets[i], abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true))
            );
        }
        assert(callIndex == callCount);
    }

    function buildFixedRateBatch(
        address safe,
        address timelock,
        address factoryAddress,
        uint256 version,
        FixedRateMarket[] memory markets
    ) internal view returns (ERPTransactionBatch memory batch, uint256 delay) {
        (batch, delay) = newTimelockBatch(safe, timelock, markets.length * 2);
        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(factoryAddress);
        for (uint256 i; i < markets.length; ++i) {
            validateFrozenAndNotPaused(markets[i].market, "Batch B");
            require(hasDebt(markets[i].market), "Batch B: debt targets reached");
            require(markets[i].fixedRateSpy <= MAX_BORROW_RATE_SPY, "Batch B: rate above IRM maximum");
            address predictedIrm = factory.predictIrmAddress(markets[i].market, version, markets[i].fixedRateSpy);
            ERPOutputWriter.addBatchCall(
                batch,
                i,
                factoryAddress,
                abi.encodeCall(OwnerFixedRateIrmFactory.deploy, (markets[i].market, version, markets[i].fixedRateSpy))
            );
            ERPOutputWriter.addBatchCall(
                batch, markets.length + i, markets[i].market, abi.encodeCall(IMarketBase.setIrm, (predictedIrm, false))
            );
        }
    }

    function validateCorrectionSchedule(ScheduleParams memory params, address timelock, address[] memory markets)
        internal
        view
        returns (uint256 aprFloorSpy, uint256 previousAprFloorSpy)
    {
        require(params.t0 <= block.timestamp, "Batch B: T0 is in the future");
        require(params.lastExecutedStep + 1 == params.step, "Batch B: steps must be sequential");

        if (params.schedulePhase == SCHEDULED) {
            (uint256 offset, uint256 aprFloor) = scheduledStep(params.severity, params.step);
            require(block.timestamp >= params.t0 + offset, "Batch B: scheduled step is not due");
            if (params.step == 1) {
                require(params.lastStepExecutedAt == 0, "Batch B: unexpected prior step timestamp");
                require(params.lastOperationId == bytes32(0), "Batch B: unexpected prior operation");
            } else {
                require(params.lastStepExecutedAt != 0, "Batch B: missing prior execution timestamp");
                require(params.lastStepExecutedAt <= block.timestamp, "Batch B: prior execution is in the future");
                (, uint256 previousAprFloor) = scheduledStep(params.severity, params.step - 1);
                validatePriorOperationExecuted(timelock, params.lastOperationId);
                previousAprFloorSpy = aprToSpy(previousAprFloor);
            }
            aprFloorSpy = aprToSpy(aprFloor);
            return (aprFloorSpy, previousAprFloorSpy);
        }

        if (params.schedulePhase == TERMINAL) {
            require(params.lastStepExecutedAt != 0, "Batch B: missing prior execution timestamp");
            require(params.lastStepExecutedAt <= block.timestamp, "Batch B: prior execution is in the future");
            require(
                block.timestamp >= params.t0 + terminalOffset(params.severity), "Batch B: terminal phase is not due"
            );
            require(
                block.timestamp >= params.lastStepExecutedAt + TERMINAL_STEP_INTERVAL,
                "Batch B: terminal step interval not elapsed"
            );
            require(debtBearingMarketCount(markets) != 0, "Batch B: debt targets reached");
            validatePriorOperationExecuted(timelock, params.lastOperationId);
            aprFloorSpy = aprToSpy(terminalAprFloor(params.severity));
            previousAprFloorSpy = aprFloorSpy;
            return (aprFloorSpy, previousAprFloorSpy);
        }

        revert("Batch B: invalid schedule phase");
    }

    function validateRateCorrection(
        address market,
        address fixedRateIrm,
        address liquidationEngine,
        uint256 borrowRateSpy,
        uint256 aprFloorSpy,
        uint256 previousAprFloorSpy,
        uint256 lastStepExecutedAt
    ) internal view {
        validateDedicatedFixedRateIrm(market, fixedRateIrm);
        validateLiquidationEngine(market, liquidationEngine);
        validateCorrectionRate(fixedRateIrm, borrowRateSpy, aprFloorSpy, previousAprFloorSpy, lastStepExecutedAt);
    }

    function validateDedicatedFixedRateIrm(address market, address fixedRateIrm) internal view {
        require(IIrm(fixedRateIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Batch B: IRM is not fixed-rate");
        require(FixedRateIrm(fixedRateIrm).market() == market, "Batch B: IRM not dedicated");
    }

    function validateLiquidationEngine(address market, address liquidationEngine) internal view {
        require(
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).market() == market, "Batch B: wrong liquidation engine"
        );
    }

    function validateCorrectionRate(
        address fixedRateIrm,
        uint256 borrowRateSpy,
        uint256 aprFloorSpy,
        uint256 previousAprFloorSpy,
        uint256 lastStepExecutedAt
    ) internal view {
        require(borrowRateSpy <= FixedRateIrm(fixedRateIrm).MAX_BORROW_RATE(), "Batch B: rate above IRM maximum");
        require(borrowRateSpy >= aprFloorSpy, "Batch B: rate below schedule APR floor");
        (uint256 currentBorrowRate, uint48 lastRateUpdate) = FixedRateIrm(fixedRateIrm).irState();
        require(currentBorrowRate >= previousAprFloorSpy, "Batch B: previous step not executed");
        require(borrowRateSpy >= currentBorrowRate, "Batch B: rate below current rate");
        if (lastStepExecutedAt != 0) {
            require(lastRateUpdate >= lastStepExecutedAt, "Batch B: prior execution not reflected in IRM");
        }
    }

    function appendRateUpdateCall(
        ERPTransactionBatch memory batch,
        uint256 callIndex,
        address fixedRateIrm,
        uint256 borrowRateSpy
    ) internal pure returns (uint256) {
        return ERPOutputWriter.addBatchCall(
            batch, callIndex, fixedRateIrm, abi.encodeCall(FixedRateIrm.setBorrowRate, (borrowRateSpy))
        );
    }

    function appendLtvUpdateCalls(
        ERPTransactionBatch memory batch,
        uint256 callIndex,
        address market,
        address liquidationEngine,
        uint256 reducedMarketMaxLtv,
        LiquidationConfiguration memory configuration
    ) internal pure returns (uint256) {
        callIndex = ERPOutputWriter.addBatchCall(
            batch, callIndex, market, abi.encodeCall(IMarketBase.setMaxLtv, (reducedMarketMaxLtv))
        );
        return ERPOutputWriter.addBatchCall(
            batch,
            callIndex,
            liquidationEngine,
            abi.encodeCall(IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (configuration))
        );
    }

    function reducedLtvConfiguration(address market, address liquidationEngine, uint256 reduction)
        internal
        view
        returns (uint256 reducedMarketMaxLtv, LiquidationConfiguration memory configuration)
    {
        validateLtvReduction(reduction);
        configuration = IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        reducedMarketMaxLtv = saturatingSub(IMarketBase(market).maxLtv(), reduction);
        configuration.maxLiquidationLtv = saturatingSub(configuration.maxLiquidationLtv, reduction);
        configuration.ltvForCompleteLiquidation = saturatingSub(configuration.ltvForCompleteLiquidation, reduction);
        require(
            reducedMarketMaxLtv <= configuration.maxLiquidationLtv
                && configuration.maxLiquidationLtv <= configuration.ltvForCompleteLiquidation,
            "Batch B: invalid LTV order"
        );
    }

    function validateLtvReduction(uint256 reduction) internal pure {
        require(reduction <= MAX_LTV_REDUCTION, "Batch B: LTV reduction above maximum");
    }

    function validateFrozenAndNotPaused(address market, string memory batchName) internal view {
        require(IMarketBase(market).paused(FROZEN_TYPE), string.concat(batchName, ": market not frozen"));
        require(!IMarketBase(market).paused(PAUSE_TYPE), string.concat(batchName, ": market paused"));
    }

    function validateRecoveryExitRoutes(address market, address adapter) internal view {
        require(IMarket(market).oracle() != address(0), "Batch C: market oracle unavailable");
        require(AdapterContractApproval(adapter).isApprovedContract(market), "Batch C: adapter route unavailable");
    }

    function validateCommonSimulationLimits(
        uint256 liquidationFundingAssets,
        uint256 badDebtAssets,
        uint256 maxLiquidationFundingAssets,
        uint256 maxBadDebtAssets
    ) internal pure {
        require(liquidationFundingAssets <= maxLiquidationFundingAssets, "Simulation: funding limit exceeded");
        require(badDebtAssets <= maxBadDebtAssets, "Simulation: bad debt limit exceeded");
    }

    function hasDebt(address market) internal view returns (bool) {
        Balance memory borrowed = IMarket(market).totalBorrowed();
        return borrowed.assets != 0 || borrowed.shares != 0;
    }

    function debtBearingMarketCount(address[] memory markets) internal view returns (uint256 count) {
        for (uint256 i; i < markets.length; ++i) {
            if (hasDebt(markets[i])) ++count;
        }
    }

    function loadRecoveryIntegrationStates(
        RecoveryMarket[] memory markets,
        address liquidationPeriphery,
        address registry,
        bool mintRegistry
    ) internal view returns (RecoveryIntegrationState[] memory states, uint256 callCount) {
        states = new RecoveryIntegrationState[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            AltoLeverage leverage = AltoLeverage(markets[i].leverage);
            IAltoLeverageSwapper swapper = leverage.swapper();
            RecoveryIntegrationState memory state = RecoveryIntegrationState({
                leverageSwapper: address(swapper),
                leverageSupported: leverage.supportedMarkets(markets[i].market),
                callbackAuthorized: IMarket(markets[i].market).authorizedCallbacks(address(leverage)),
                swapperWhitelisted: swapper.isWhitelisted(address(leverage)),
                liquidationSupported: ILiquidationPeripheryBase(liquidationPeriphery)
                    .supportedMarkets(markets[i].market),
                liquidationAuthorized: IMarket(markets[i].market).authorizedLiquidationPeriphery(liquidationPeriphery),
                registered: mintRegistry
                    ? IMarketRegistry(registry).isMintMarket(markets[i].market)
                    : IMarketRegistry(registry).isBorrowMarket(markets[i].market)
            });
            states[i] = state;
            if (state.leverageSupported) ++callCount;
            if (state.callbackAuthorized) ++callCount;
            if (state.swapperWhitelisted) ++callCount;
            if (state.liquidationSupported) ++callCount;
            if (state.liquidationAuthorized) ++callCount;
            if (state.registered) ++callCount;
        }
    }

    function appendRecoveryIntegrationRemovalCalls(
        RecoveryMarket[] memory markets,
        RecoveryIntegrationState[] memory states,
        address liquidationPeriphery,
        address registry,
        bool mintRegistry,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) internal pure returns (uint256) {
        callIndex = appendLeverageRemovalCalls(markets, states, batch, callIndex);
        callIndex = appendLiquidationRemovalCalls(markets, states, liquidationPeriphery, batch, callIndex);
        return appendRegistryRemovalCalls(markets, states, registry, mintRegistry, batch, callIndex);
    }

    function appendLeverageRemovalCalls(
        RecoveryMarket[] memory markets,
        RecoveryIntegrationState[] memory states,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) internal pure returns (uint256) {
        for (uint256 i; i < markets.length; ++i) {
            RecoveryIntegrationState memory state = states[i];
            if (state.leverageSupported) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    markets[i].leverage,
                    abi.encodeCall(AltoLeverage.setMarket, (markets[i].market, false))
                );
            }
            if (state.callbackAuthorized) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    markets[i].market,
                    abi.encodeCall(IMarketBase.setAuthorizedCallback, (markets[i].leverage, false))
                );
            }
            if (state.swapperWhitelisted) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    state.leverageSwapper,
                    abi.encodeCall(IAltoLeverageSwapper.setWhitelisted, (markets[i].leverage, false))
                );
            }
        }
        return callIndex;
    }

    function appendLiquidationRemovalCalls(
        RecoveryMarket[] memory markets,
        RecoveryIntegrationState[] memory states,
        address liquidationPeriphery,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) internal pure returns (uint256) {
        for (uint256 i; i < markets.length; ++i) {
            if (states[i].liquidationSupported) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    liquidationPeriphery,
                    abi.encodeCall(ILiquidationPeripheryBase.setSupportedMarket, (markets[i].market, false))
                );
            }
            if (states[i].liquidationAuthorized) {
                callIndex = ERPOutputWriter.addBatchCall(
                    batch,
                    callIndex,
                    markets[i].market,
                    abi.encodeCall(IMarketBase.setAuthorizedLiquidationPeriphery, (liquidationPeriphery, false))
                );
            }
        }
        return callIndex;
    }

    function appendRegistryRemovalCalls(
        RecoveryMarket[] memory markets,
        RecoveryIntegrationState[] memory states,
        address registry,
        bool mintRegistry,
        ERPTransactionBatch memory batch,
        uint256 callIndex
    ) internal pure returns (uint256) {
        for (uint256 i; i < markets.length; ++i) {
            if (!states[i].registered) continue;
            bytes memory data = mintRegistry
                ? abi.encodeCall(IMarketRegistry.removeMintMarket, (markets[i].market))
                : abi.encodeCall(IMarketRegistry.removeBorrowMarket, (markets[i].market));
            callIndex = ERPOutputWriter.addBatchCall(batch, callIndex, registry, data);
        }
        return callIndex;
    }

    function scheduledStep(uint8 severity, uint256 step) internal pure returns (uint256 offset, uint256 aprFloor) {
        if (severity == MEDIUM) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (7 days, 0.2 ether);
            if (step == 3) return (14 days, 0.4 ether);
            if (step == 4) return (21 days, 0.8 ether);
        } else if (severity == HIGH) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (4 days, 0.2 ether);
            if (step == 3) return (7 days, 0.4 ether);
            if (step == 4) return (10 days, 0.8 ether);
        } else if (severity == CRITICAL) {
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

    function terminalOffset(uint8 severity) internal pure returns (uint256) {
        if (severity == MEDIUM) return 28 days;
        if (severity == HIGH) return 14 days;
        if (severity == CRITICAL) return 7 days;
        revert("Batch B: invalid severity");
    }

    function terminalAprFloor(uint8 severity) internal pure returns (uint256) {
        return severity == CRITICAL ? 3.2 ether : 0.8 ether;
    }

    function aprToSpy(uint256 apr) internal pure returns (uint256) {
        return apr / YEAR;
    }

    function saturatingSub(uint256 value, uint256 reduction) internal pure returns (uint256) {
        return value > reduction ? value - reduction : 0;
    }

    function validatePriorOperationExecuted(address timelock, bytes32 operationId) internal view {
        require(operationId != bytes32(0), "Batch B: missing prior operation");
        require(
            TimelockController(payable(timelock)).isOperationDone(operationId), "Batch B: prior operation not executed"
        );
    }
}
