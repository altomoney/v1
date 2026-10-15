// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MintMarketOffboardingTestBase} from "./MintMarketOffboardingTestBase.sol";
import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
import {MintMarketOffboardingIO} from "../libraries/MintMarketOffboardingIO.sol";
import {
    MintMarketOffboardingManifest,
    MintMarketOffboardingPhase,
    MintMarketOffboardingSchedulePhase,
    MintMarketOffboardingSeverity
} from "../IMintMarketOffboarding.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MintBatchBReduceLtvTest is MintMarketOffboardingTestBase {
    uint256 private constant MAX_LTV_REDUCTION = 0.05 ether;
    uint256 private constant FUNDING_LIMIT_INDEX = 0;
    uint256 private constant BAD_DEBT_LIMIT_INDEX = 1;
    uint256 private constant SEIZED_COLLATERAL_LIMIT_INDEX = 3;

    struct LtvMarketSnapshot {
        address irm;
        address liquidationEngine;
        uint256 maxLtv;
        LiquidationConfiguration liquidationConfiguration;
    }

    struct BoundaryFixture {
        address borrower;
        uint256 price;
    }

    BoundaryFixture[] private boundaryFixtures;

    function setUp() public {
        _setUpManifest();
    }

    /// @dev Executes the exact five-call correction group for every Mint Market and verifies the generated artifacts,
    /// fee mint, debt ceiling, fixed rate, independently reduced LTVs, unchanged liquidation fields, and frozen entry.
    function testBatchBGeneratesAndExecutesExactMintCorrectionCalls() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-exact-calls");
        LtvMarketSnapshot[] memory beforeState = _marketSnapshots();
        uint256[] memory mintedBefore = new uint256[](mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            (mintedBefore[i],) = dusd.minterConfig(mintMarkets[i]);
        }

        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        input = scriptHarness.runPhase(phase, manifest, input);
        bytes32 operationId = _assertGeneratedArtifacts(beforeState, bytes32(0), mintMarkets.length);
        _executeTimelockArtifacts(phase, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE);

        assertTrue(timelock.isOperationDone(operationId), "correction operation was not executed");
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertReduction(i, beforeState[i]);
            assertEq(AltoMintMarket(mintMarkets[i]).claimableFeesAssets(), 0, "fees remain claimable");
            (uint256 mintedAfter,) = dusd.minterConfig(mintMarkets[i]);
            assertEq(mintedAfter - mintedBefore[i], manifest.markets[i].maxDusdMintedAssets, "wrong DUSD fee mint");
            assertEq(
                IMarket(mintMarkets[i]).totalSupply().assets, manifest.markets[i].debtCeiling, "wrong debt ceiling"
            );
            _assertEntrancesBlocked(i);
        }
    }

    /// @dev Executes every Medium scheduled step and its first terminal step, checking rate floors, exact reductions,
    /// operation predecessors, and the T+28 terminal gate.
    function testScheduledMediumSeverity() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-medium");
        _executeSeveritySchedule(MintMarketOffboardingSeverity.MEDIUM);
    }

    /// @dev Executes every High scheduled step and its first terminal step, checking rate floors, exact reductions,
    /// operation predecessors, and the T+14 terminal gate.
    function testScheduledHighSeverity() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-high");
        _executeSeveritySchedule(MintMarketOffboardingSeverity.HIGH);
    }

    /// @dev Executes every Critical scheduled step and its first terminal step, checking daily rate/LTV corrections,
    /// predecessor chaining, and the T+7 terminal gate.
    function testScheduledCriticalSeverity() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-critical");
        _executeSeveritySchedule(MintMarketOffboardingSeverity.CRITICAL);
    }

    /// @dev Makes one market report zero debt and verifies its five-call group is omitted while all outstanding markets
    /// remain ordered and receive the exact approved correction calls.
    function testBatchBSkipsClearedMarketAndContinuesOutstandingMarkets() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-skip-cleared");
        LtvMarketSnapshot[] memory beforeState = _marketSnapshots();
        vm.mockCall(
            mintMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
        );

        input = scriptHarness.runPhase(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, input);
        _assertGeneratedArtifacts(beforeState, bytes32(0), mintMarkets.length - 1);
        _executeTimelockArtifacts(
            MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );

        assertEq(IMarket(mintMarkets[0]).maxLtv(), beforeState[0].maxLtv, "cleared market LTV changed");
        for (uint256 i = 1; i < mintMarkets.length; ++i) {
            _assertReduction(i, beforeState[i]);
        }
    }

    /// @dev Sets the three thresholds to 2%, 4%, and 8%, then verifies a five-point reduction independently saturates
    /// them to 0%, 0%, and 3%.
    function testBatchBSaturatesEachLtvThresholdIndependentlyAtZero() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-saturating");
        IMarket market = IMarket(mintMarkets[0]);
        IDcfDlbPriorityLiquidationEngine engine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory configuration = engine.liquidationConfiguration();
        configuration.maxLiquidationLtv = 0.04 ether;
        configuration.ltvForCompleteLiquidation = 0.08 ether;

        vm.startPrank(address(timelock));
        market.setMaxLtv(0.02 ether);
        engine.setLiquidationConfiguration(configuration);
        vm.stopPrank();
        for (uint256 i = 1; i < mintMarkets.length; ++i) {
            vm.mockCall(
                mintMarkets[i], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
            );
        }
        manifest.markets[0].ltvReduction = MAX_LTV_REDUCTION;

        _executeTimelockPhase(
            MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );
        configuration = engine.liquidationConfiguration();
        assertEq(market.maxLtv(), 0, "market LTV did not saturate");
        assertEq(configuration.maxLiquidationLtv, 0, "liquidation LTV did not saturate");
        assertEq(configuration.ltvForCompleteLiquidation, 0.03 ether, "complete-liquidation LTV is wrong");
    }

    /// @dev Runs the operational simulation with the complete fork borrower inventory and boundary positions, verifying
    /// share reconciliation, newly liquidatable classification, liquidation outcomes, and Mint/DUSD aggregate evidence.
    function testBatchBSimulationReportsNewLiquidationsAndDusdAccounting() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-simulation");
        uint256[4] memory limits = _permissiveLimits();
        string memory manifestPath = _writeSimulationInputs("mint-reduce-ltv-simulation-run", limits);

        scriptHarness.run(uint256(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);

        string memory outputDirectory = _simulationOutputDirectory(manifestPath);
        string memory report = vm.readFile(string.concat(outputDirectory, "/simulation-report.json"));
        assertTrue(vm.parseJsonBool(report, ".passed"), "simulation report did not pass");
        assertEq(
            vm.parseJsonString(report, ".operationId"),
            vm.toString(_correctionOperationId()),
            "simulation operation ID mismatch"
        );

        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertBorrowerListComplete(i);
            _assertBoundaryResult(report, boundaryFixtures[i].borrower);
            uint256 funding = vm.parseJsonUint(
                report, string.concat(".markets[", vm.toString(i), "].totals.liquidationFundingAssets")
            );
            uint256 burned =
                vm.parseJsonUint(report, string.concat(".markets[", vm.toString(i), "].totals.dusdBurnedAssets"));
            assertEq(burned, funding, "reported DUSD burn does not match funding");
        }
    }

    /// @dev Reports less aggregate market-attributed DUSD than the simulated liquidations require and verifies the
    /// simulation rejects the batch instead of saturating the remaining minted balance to zero.
    function testBatchBSimulationRejectsAggregateFundingAboveDusdMinted() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-dusd-funding");
        string memory manifestPath = _writeSimulationInputs("mint-reduce-ltv-dusd-funding-run", _permissiveLimits());
        vm.mockCall(
            address(dusd),
            abi.encodeCall(IDUSD.minterConfig, (mintMarkets[0])),
            abi.encode(uint256(0), type(uint256).max)
        );

        vm.expectRevert(bytes("Simulation: liquidation funding exceeds DUSD minted"));
        scriptHarness.run(uint256(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);
    }

    /// @dev Reuses the same pending and ready Timelock operation during repeated simulations and verifies the fork
    /// snapshot prevents either simulation from completing or replacing the real scheduled operation.
    function testBatchBSimulationReusesPendingAndReadyTimelockOperation() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-resimulation");
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        bytes32 operationId = _correctionOperationId();
        input = scriptHarness.runPhase(phase, manifest, input);
        _executeSafeBatch(phase, REDUCE_LTV_SCHEDULE_FILE, manifest.timelockSafe);

        uint256[4] memory limits = _permissiveLimits();
        string memory manifestPath = _writeSimulationInputs("mint-reduce-ltv-resimulation-run", limits);
        scriptHarness.run(uint256(phase), manifestPath);
        assertTrue(timelock.isOperationPending(operationId), "pending operation was lost");
        assertFalse(timelock.isOperationDone(operationId), "simulation executed pending operation");

        vm.warp(timelock.getTimestamp(operationId));
        scriptHarness.run(uint256(phase), manifestPath);
        assertTrue(timelock.isOperationReady(operationId), "ready operation changed state");
        assertFalse(timelock.isOperationDone(operationId), "simulation executed ready operation");
    }

    /// @dev Forces nonzero liquidation funding, bad debt, and seized collateral, then verifies each zero approved limit
    /// rejects the simulation independently and removes stale operational artifacts.
    function testBatchBSimulationRejectsExceededMintLimitsWithoutWritingArtifacts() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-limits");
        vm.mockCall(
            IMarket(mintMarkets[0]).oracle(),
            abi.encodeCall(IOracle.getPrice, ()),
            abi.encode(boundaryFixtures[0].price / 2)
        );
        _assertSimulationLimitFailure("mint-funding-limit", FUNDING_LIMIT_INDEX, "Simulation: funding limit exceeded");
        _assertSimulationLimitFailure(
            "mint-bad-debt-limit", BAD_DEBT_LIMIT_INDEX, "Simulation: bad debt limit exceeded"
        );
        _assertSimulationLimitFailure(
            "mint-seized-limit", SEIZED_COLLATERAL_LIMIT_INDEX, "Simulation: seized collateral limit exceeded"
        );
    }

    /// @dev Mocks an active borrower's liquidation with an unexpected error and verifies the simulation bubbles it
    /// instead of classifying the borrower as solvent.
    function testBatchBSimulationAbortsOnUnexpectedLiquidationRevert() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-unexpected-revert");
        string memory manifestPath =
            _writeSimulationInputs("mint-reduce-ltv-unexpected-revert-run", _permissiveLimits());
        address borrower = _activeBorrower(0);
        bytes memory callData = abi.encodeCall(IMarketBase.liquidate, (borrower, bytes(""), bytes("")));
        bytes memory unexpectedError = abi.encodeWithSignature("Error(string)", "unexpected liquidation failure");
        vm.mockCallRevert(mintMarkets[0], callData, unexpectedError);

        vm.expectRevert(unexpectedError);
        scriptHarness.run(uint256(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);
    }

    /// @dev Makes all markets report zero debt and verifies the phase stops before writing schedule, execute, inputs,
    /// or simulation-report artifacts.
    function testBatchBStopsWhenAllDebtTargetsAreReached() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-cleared");
        string memory manifestPath = _writeSimulationInputs("mint-reduce-ltv-cleared-run", _permissiveLimits());
        string memory outputDirectory = _simulationOutputDirectory(manifestPath);
        for (uint256 i; i < mintMarkets.length; ++i) {
            vm.mockCall(
                mintMarkets[i], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
            );
        }

        vm.expectRevert(bytes("Batch B: debt targets reached"));
        scriptHarness.run(uint256(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);
        _assertNoSimulationOutputs(outputDirectory);
    }

    /// @dev Verifies scheduled corrections reject early execution, rates below the schedule/current rate, and reductions
    /// above the five-percentage-point maximum.
    function testBatchBRejectsInvalidScheduledInputs() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-invalid-schedule");
        vm.warp(manifest.t0 + 1 days - 1);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: scheduled step is not due");

        vm.warp(manifest.t0 + 1 days);
        uint256 belowFloor = 0.1 ether / uint256(365 days) - 1;
        _setCorrectionInputs(belowFloor, MAX_LTV_REDUCTION);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: rate below schedule APR floor");

        _setCorrectionInputs(0.1 ether / uint256(365 days), MAX_LTV_REDUCTION);
        address currentIrm = IMarket(mintMarkets[0]).irm();
        vm.prank(address(timelock));
        FixedRateIrm(currentIrm).setBorrowRate(manifest.markets[0].correctionRateSpy + 1);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: rate below current rate");

        _setCorrectionInputs(0.2 ether / uint256(365 days), MAX_LTV_REDUCTION + 1);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: LTV reduction above maximum");
    }

    /// @dev Verifies correction generation requires every debt-bearing market to stay frozen but not fully paused.
    function testBatchBRejectsInvalidPauseState() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-pause-state");
        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[0]).pause(FROZEN_TYPE, false);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: market not frozen");

        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[0]).pause(FROZEN_TYPE, true);
        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[0]).pause(PAUSE_TYPE, true);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: market paused");
    }

    /// @dev Verifies generation rejects an increased debt ceiling, a target below exposure, an unapproved fee mint,
    /// and insufficient DUSD ceiling capacity for the exact claim.
    function testBatchBRejectsInvalidMintAccountingTargets() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-accounting");
        IMarket market = IMarket(mintMarkets[0]);

        manifest.markets[0].debtCeiling = market.totalSupply().assets + 1;
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: debt ceiling increase");

        manifest.markets[0].debtCeiling =
            market.totalBorrowed().assets + AltoMintMarket(mintMarkets[0]).badDebtAssets() - 1;
        _expectPhaseRevert(
            MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: debt ceiling below current exposure"
        );

        manifest.markets[0].debtCeiling = market.totalSupply().assets;
        manifest.markets[0].maxDusdMintedAssets = AltoMintMarket(mintMarkets[0]).claimableFeesAssets() - 1;
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: DUSD mint limit exceeded");

        manifest.markets[0].maxDusdMintedAssets = type(uint256).max;
        (uint256 minted,) = dusd.minterConfig(mintMarkets[0]);
        vm.prank(address(timelock));
        dusd.setMinterCeiling(mintMarkets[0], minted);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: insufficient DUSD mint capacity");
    }

    /// @dev Verifies terminal corrections cannot skip steps and cannot run less than one hour after the prior step.
    function testTerminalStepRejectsCatchUpAndSubHourlyExecution() public {
        _prepareFixedRateMarkets("mint-reduce-ltv-terminal-rejections");
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.TERMINAL;
        manifest.t0 = block.timestamp - 28 days;
        manifest.step = 3;
        manifest.lastExecutedStep = 1;
        manifest.lastStepExecutedAt = block.timestamp - 6 hours;
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: steps must be sequential");

        manifest.step = 2;
        manifest.lastStepExecutedAt = block.timestamp - 1 hours + 1;
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: terminal step interval not elapsed");
    }

    function _prepareFixedRateMarkets(string memory activationId) private {
        _seedBoundaryPositions();
        _setApprovedContainmentTargets();
        _executeBatchBFixedRate(activationId);
        assertEq(block.number, _forkBlock() + 2, "fixed-rate execution block mismatch");

        manifest.t0 = block.timestamp;
        manifest.severity = MintMarketOffboardingSeverity.MEDIUM;
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.SCHEDULED;
        manifest.step = 1;
        manifest.lastExecutedStep = 0;
        manifest.lastStepExecutedAt = 0;
        manifest.lastOperationId = bytes32(0);
        _advanceTo(manifest.t0 + 1 days);
        _setCorrectionInputs(0.1 ether / uint256(365 days), MAX_LTV_REDUCTION);
        _prepareCorrectionTargets();
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertBorrowerListComplete(i);
        }
    }

    function _seedBoundaryPositions() private {
        vm.startPrank(address(timelock));
        for (uint256 i; i < mintMarkets.length; ++i) {
            AltoMintMarket(mintMarkets[i]).setDebtCeiling(TEMPORARY_CEILING);
            dusd.setMinterCeiling(mintMarkets[i], TEMPORARY_CEILING);
        }
        vm.stopPrank();

        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            uint256 livePrice = IOracle(market.oracle()).getPrice();
            uint256 collateralAssets = 10 ** uint256(IERC20Metadata(market.collateralToken()).decimals()) / 100;
            uint256 collateralValue = Math.mulDiv(collateralAssets, livePrice, LENDING_ORACLE_PRICE_PRECISION);
            uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);
            uint256 targetDebt = maximumBorrow - maximumBorrow / 1_000_000;
            uint256 borrowAssets = Math.mulDiv(targetDebt, 1 ether, 1 ether + market.borrowOpeningFee()) - 1;
            address borrower = makeAddr(string.concat("mint-boundary-borrower-", vm.toString(i)));
            _openMintPosition(market, borrower, collateralAssets, borrowAssets);
            _registerTestBorrower(i, borrower);

            uint256 maxLiquidationLtv =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .liquidationConfiguration()
            .maxLiquidationLtv;
            uint256 targetLtv = maxLiquidationLtv - MAX_LTV_REDUCTION / 2;
            uint256 boundaryPrice = Math.mulDiv(livePrice, market.maxLtv(), targetLtv);
            boundaryFixtures.push(BoundaryFixture({borrower: borrower, price: boundaryPrice}));
            vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(boundaryPrice));
        }
    }

    function _executeSeveritySchedule(MintMarketOffboardingSeverity severity) private {
        manifest.severity = severity;
        uint256 stepCount = severity == MintMarketOffboardingSeverity.CRITICAL ? 6 : 4;
        for (uint256 step = 1; step <= stepCount; ++step) {
            (uint256 offset, uint256 apr) = _scheduledStep(severity, step);
            if (block.timestamp < manifest.t0 + offset) _advanceTo(manifest.t0 + offset);
            manifest.step = step;
            manifest.schedulePhase = MintMarketOffboardingSchedulePhase.SCHEDULED;
            _setCorrectionInputs(apr / uint256(365 days), MAX_LTV_REDUCTION);
            manifest.markets[0].ltvReduction = 0.03 ether;
            _prepareCorrectionTargets();
            _executeCorrectionStep();
        }

        uint256 terminalOffset = severity == MintMarketOffboardingSeverity.MEDIUM
            ? 28 days
            : severity == MintMarketOffboardingSeverity.HIGH ? 14 days : 7 days;
        uint256 terminalAt = manifest.t0 + terminalOffset;
        uint256 hourlyAt = manifest.lastStepExecutedAt + 1 hours;
        if (hourlyAt > terminalAt) terminalAt = hourlyAt;
        if (block.timestamp < terminalAt) _advanceTo(terminalAt);
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.TERMINAL;
        manifest.step = manifest.lastExecutedStep + 1;
        uint256 terminalApr = severity == MintMarketOffboardingSeverity.CRITICAL ? 3.2 ether : 0.8 ether;
        _setCorrectionInputs(terminalApr / uint256(365 days), MAX_LTV_REDUCTION);
        _prepareCorrectionTargets();

        _executeCorrectionStep();
        _assertAllFrozenAndUnpaused();
    }

    function _executeCorrectionStep() private {
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        LtvMarketSnapshot[] memory beforeState = _marketSnapshots();
        bytes32 predecessor = manifest.lastOperationId;
        input = scriptHarness.runPhase(phase, manifest, input);
        bytes32 operationId = _assertGeneratedArtifacts(beforeState, predecessor, mintMarkets.length);
        bytes32 executedOperationId =
            _executeTimelockArtifacts(phase, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE);
        assertEq(executedOperationId, operationId, "executed correction operation mismatch");

        manifest.lastExecutedStep = manifest.step;
        manifest.lastStepExecutedAt = block.timestamp;
        manifest.lastOperationId = operationId;
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertReduction(i, beforeState[i]);
        }
    }

    function _scheduledStep(MintMarketOffboardingSeverity severity, uint256 step)
        private
        pure
        returns (uint256 offset, uint256 apr)
    {
        if (severity == MintMarketOffboardingSeverity.MEDIUM) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (7 days, 0.2 ether);
            if (step == 3) return (14 days, 0.4 ether);
            return (21 days, 0.8 ether);
        }
        if (severity == MintMarketOffboardingSeverity.HIGH) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (4 days, 0.2 ether);
            if (step == 3) return (7 days, 0.4 ether);
            return (10 days, 0.8 ether);
        }
        if (step == 1) return (1 days, 0.1 ether);
        if (step == 2) return (2 days, 0.2 ether);
        if (step == 3) return (3 days, 0.4 ether);
        if (step == 4) return (4 days, 0.8 ether);
        if (step == 5) return (5 days, 1.6 ether);
        return (6 days, 3.2 ether);
    }

    function _marketSnapshots() private view returns (LtvMarketSnapshot[] memory snapshots) {
        snapshots = new LtvMarketSnapshot[](mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            address engine = market.liquidationEngine();
            snapshots[i] = LtvMarketSnapshot({
                irm: market.irm(),
                liquidationEngine: engine,
                maxLtv: market.maxLtv(),
                liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(engine).liquidationConfiguration()
            });
        }
    }

    function _assertGeneratedArtifacts(
        LtvMarketSnapshot[] memory beforeState,
        bytes32 expectedPredecessor,
        uint256 expectedMarketCount
    ) private view returns (bytes32 operationId) {
        TimelockArtifactBatch memory scheduled;
        (scheduled, operationId) = _loadAndAssertTimelockPair(
            MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV,
            REDUCE_LTV_SCHEDULE_FILE,
            REDUCE_LTV_EXECUTE_FILE,
            expectedPredecessor
        );
        _assertCorrectionCalls(scheduled, beforeState, expectedMarketCount);
    }

    function _assertCorrectionCalls(
        TimelockArtifactBatch memory batch,
        LtvMarketSnapshot[] memory beforeState,
        uint256 expectedMarketCount
    ) private view {
        _assertTimelockCallCount(batch, expectedMarketCount * 5);
        uint256 callIndex;
        for (uint256 i; i < mintMarkets.length; ++i) {
            Balance memory borrowed = IMarket(mintMarkets[i]).totalBorrowed();
            if (borrowed.assets == 0 && borrowed.shares == 0) continue;
            LiquidationConfiguration memory configuration =
                IDcfDlbPriorityLiquidationEngine(beforeState[i].liquidationEngine).liquidationConfiguration();
            uint256 reduction = manifest.markets[i].ltvReduction;
            configuration.maxLiquidationLtv = _saturatingSub(configuration.maxLiquidationLtv, reduction);
            configuration.ltvForCompleteLiquidation = _saturatingSub(configuration.ltvForCompleteLiquidation, reduction);

            _assertTimelockCall(
                batch,
                callIndex,
                beforeState[i].irm,
                abi.encodeCall(FixedRateIrm.setBorrowRate, (manifest.markets[i].correctionRateSpy))
            );
            _assertTimelockCall(batch, callIndex + 1, mintMarkets[i], abi.encodeCall(AltoMintMarket.claimInterest, (0)));
            _assertTimelockCall(
                batch,
                callIndex + 2,
                mintMarkets[i],
                abi.encodeCall(
                    IMarketBase.setMaxLtv, (_saturatingSub(beforeState[i].maxLtv, manifest.markets[i].ltvReduction))
                )
            );
            _assertTimelockCall(
                batch,
                callIndex + 3,
                beforeState[i].liquidationEngine,
                abi.encodeCall(IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (configuration))
            );
            _assertTimelockCall(
                batch,
                callIndex + 4,
                mintMarkets[i],
                abi.encodeCall(AltoMintMarket.setDebtCeiling, (manifest.markets[i].debtCeiling))
            );
            callIndex += 5;
        }
        assertEq(callIndex, expectedMarketCount * 5, "wrong grouped market count");
    }

    function _assertReduction(uint256 marketIndex, LtvMarketSnapshot memory beforeState) private view {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        LiquidationConfiguration memory afterConfiguration =
            IDcfDlbPriorityLiquidationEngine(beforeState.liquidationEngine).liquidationConfiguration();
        uint256 reduction = manifest.markets[marketIndex].ltvReduction;
        assertEq(market.irm(), beforeState.irm, "IRM changed");
        assertEq(market.liquidationEngine(), beforeState.liquidationEngine, "liquidation engine changed");
        assertEq(market.maxLtv(), _saturatingSub(beforeState.maxLtv, reduction), "wrong market max LTV");
        assertEq(
            afterConfiguration.maxLiquidationLtv,
            _saturatingSub(beforeState.liquidationConfiguration.maxLiquidationLtv, reduction),
            "wrong liquidation LTV"
        );
        assertEq(
            afterConfiguration.ltvForCompleteLiquidation,
            _saturatingSub(beforeState.liquidationConfiguration.ltvForCompleteLiquidation, reduction),
            "wrong complete-liquidation LTV"
        );
        (uint256 rate,) = FixedRateIrm(beforeState.irm).irState();
        assertEq(rate, manifest.markets[marketIndex].correctionRateSpy, "wrong corrected rate");
        assertLe(market.maxLtv(), afterConfiguration.maxLiquidationLtv, "market/liquidation LTV order invalid");
        assertLe(
            afterConfiguration.maxLiquidationLtv,
            afterConfiguration.ltvForCompleteLiquidation,
            "liquidation threshold order invalid"
        );
        _assertUnscheduledFieldsUnchanged(beforeState.liquidationConfiguration, afterConfiguration);
        _assertFrozenAndUnpaused(market);
    }

    function _assertUnscheduledFieldsUnchanged(
        LiquidationConfiguration memory beforeConfig,
        LiquidationConfiguration memory afterConfig
    ) private pure {
        assertEq(afterConfig.dynamicBonusFeeStart, beforeConfig.dynamicBonusFeeStart, "dynamic bonus changed");
        assertEq(
            afterConfig.dynamicBonusFeeDecaySteepness, beforeConfig.dynamicBonusFeeDecaySteepness, "bonus decay changed"
        );
        assertEq(afterConfig.liquidationBaseFee, beforeConfig.liquidationBaseFee, "base fee changed");
        assertEq(afterConfig.minPenaltyPercentage, beforeConfig.minPenaltyPercentage, "minimum penalty changed");
        assertEq(afterConfig.protocolFeePercentage, beforeConfig.protocolFeePercentage, "protocol fee changed");
        assertEq(
            afterConfig.isEnabledPriorityLiquidation, beforeConfig.isEnabledPriorityLiquidation, "priority flag changed"
        );
        assertEq(
            afterConfig.disablePriorityLiquidationAbovePositionLtv,
            beforeConfig.disablePriorityLiquidationAbovePositionLtv,
            "priority cutoff changed"
        );
        assertEq(
            afterConfig.priorityLiquidationGracePeriod,
            beforeConfig.priorityLiquidationGracePeriod,
            "priority grace changed"
        );
        assertEq(
            afterConfig.taggerLiquidationGracePeriod, beforeConfig.taggerLiquidationGracePeriod, "tagger grace changed"
        );
        assertEq(afterConfig.liquidationWindowTag, beforeConfig.liquidationWindowTag, "liquidation window changed");
    }

    function _assertBoundaryResult(string memory report, address borrower) private view {
        uint256 index;
        while (vm.keyExistsJson(report, string.concat(".borrowers[", vm.toString(index), "]"))) {
            string memory prefix = string.concat(".borrowers[", vm.toString(index), "]");
            if (vm.parseJsonAddress(report, string.concat(prefix, ".borrower")) == borrower) {
                assertFalse(
                    vm.parseJsonBool(report, string.concat(prefix, ".liquidatableBefore")),
                    "boundary liquidatable before"
                );
                assertTrue(
                    vm.parseJsonBool(report, string.concat(prefix, ".liquidatableAfter")),
                    "boundary not liquidatable after"
                );
                assertTrue(
                    vm.parseJsonBool(report, string.concat(prefix, ".newlyLiquidatable")),
                    "boundary not newly liquidatable"
                );
                assertGt(vm.parseJsonUint(report, string.concat(prefix, ".repaidBorrowAssets")), 0, "no repayment");
                assertGt(vm.parseJsonUint(report, string.concat(prefix, ".seizedCollateralAssets")), 0, "no seizure");
                return;
            }
            ++index;
        }
        revert("boundary borrower missing from report");
    }

    function _assertSimulationLimitFailure(string memory activationId, uint256 limitIndex, bytes memory expectedError)
        private
    {
        uint256[4] memory limits = _permissiveLimits();
        limits[limitIndex] = 0;
        string memory manifestPath = _writeSimulationInputs(activationId, limits);
        string memory outputDirectory = _simulationOutputDirectory(manifestPath);
        vm.writeFile(string.concat(outputDirectory, "/", REDUCE_LTV_SCHEDULE_FILE), "{}");
        vm.writeFile(string.concat(outputDirectory, "/", REDUCE_LTV_EXECUTE_FILE), "{}");
        vm.writeFile(string.concat(outputDirectory, "/inputs.json"), "{}");
        vm.writeFile(string.concat(outputDirectory, "/simulation-report.json"), "{}");

        uint256 snapshotId = vm.snapshotState();
        vm.expectRevert(expectedError);
        scriptHarness.run(uint256(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);
        assertTrue(vm.revertToState(snapshotId), "failed simulation state leaked");
        _assertNoSimulationOutputs(outputDirectory);
    }

    function _simulationOutputDirectory(string memory manifestPath) private view returns (string memory) {
        MintMarketOffboardingManifest memory simulationManifest =
            MintMarketOffboardingIO.loadActivationManifest(manifestPath);
        return
            MintMarketOffboarding.artifactDirectory(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, simulationManifest);
    }

    function _assertNoSimulationOutputs(string memory outputDirectory) private view {
        assertFalse(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_SCHEDULE_FILE)), "stale schedule remains");
        assertFalse(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_EXECUTE_FILE)), "stale execute remains");
        assertFalse(vm.exists(string.concat(outputDirectory, "/inputs.json")), "stale inputs remain");
        assertFalse(vm.exists(string.concat(outputDirectory, "/simulation-report.json")), "stale report remains");
        assertTrue(vm.exists(string.concat(outputDirectory, "/borrowers.json")), "borrowers removed");
    }

    function _activeBorrower(uint256 marketIndex) private view returns (address) {
        address[] memory borrowers = _forkBorrowers(marketIndex);
        for (uint256 i; i < borrowers.length; ++i) {
            if (IMarket(mintMarkets[marketIndex]).position(borrowers[i]).borrowShares != 0) return borrowers[i];
        }
        revert("no active borrower");
    }

    function _permissiveLimits() private pure returns (uint256[4] memory limits) {
        for (uint256 i; i < limits.length; ++i) {
            limits[i] = type(uint128).max;
        }
    }

    function _saturatingSub(uint256 value, uint256 reduction) private pure returns (uint256) {
        return value > reduction ? value - reduction : 0;
    }
}
