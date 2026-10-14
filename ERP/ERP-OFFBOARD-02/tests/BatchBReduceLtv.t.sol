// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingIO} from "../libraries/BorrowMarketOffboardingIO.sol";
import {
    BorrowMarketOffboardingManifest,
    BorrowMarketOffboardingMarket,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingSchedulePhase,
    BorrowMarketOffboardingSeverity
} from "../IBorrowMarketOffboarding.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BatchBReduceLtvTest is BorrowMarketOffboardingTestBase {
    struct LtvMarketSnapshot {
        address irm;
        address liquidationEngine;
        uint256 maxLtv;
        LiquidationConfiguration liquidationConfiguration;
    }

    struct BoundaryFixture {
        address borrower;
        address liquidator;
        uint256 price;
    }

    BoundaryFixture[] private boundaryFixtures;
    LtvMarketSnapshot[] private ltvSnapshots;

    function setUp() public {
        _setUpManifest();
    }

    function _prepareFixedRateMarkets(string memory activationId) private {
        manifest.activationId = activationId;
        _seedStandardPositions();
        _seedBoundaryPositions();
        _executeBatchBFixedRate();
        // The completed fixed-rate attachment anchors the test lifecycle's approved activation T0.
        manifest.t0 = block.timestamp;

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertHealthyAndSnapshot(i);
        }
        _advanceTo(manifest.t0 + 1 days);
    }

    /// @dev Manifest: five contained, debt-bearing markets with fixed-rate IRMs and approved per-market correction rates
    /// and LTV reductions. Executes the generated Timelock schedule/execute pair and verifies each rate and all three LTV
    /// thresholds change by exactly the approved amount while threshold ordering and unrelated configuration are kept.
    /// Also proves frozen/unpaused state and repayment, withdrawal, liquidation, and integration routes remain available.
    function testBatchBReducesLtvParametersAndPreservesExitAndLiquidationRoutes() public {
        _prepareFixedRateMarkets("reduce-ltv-routes");
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketReductionAndRoutes(i);
        }
    }

    /// @dev Manifest: Medium severity with T0 set to the current time and all markets still carrying debt.
    /// Executes scheduled steps at T+1/+7/+14/+21 days with 10%/20%/40%/80% APR floors, then the first terminal step at
    /// T+28 days. Uses an approved 3-point reduction for one market and 5 points for the others, checking every resulting
    /// rate/LTV change and preserved freeze and exit state.
    function testScheduledMediumSeverity() public {
        _prepareFixedRateMarkets("reduce-ltv-medium");
        _executeSeveritySchedule(BorrowMarketOffboardingSeverity.MEDIUM);
    }

    /// @dev Manifest: High severity with T0 set to the current time and all markets still carrying debt.
    /// Executes scheduled steps at T+1/+4/+7/+10 days with 10%/20%/40%/80% APR floors, then the first terminal step at
    /// T+14 days. Uses approved 3-point and 5-point reductions and verifies every generated Timelock operation changes
    /// only the scheduled rate/LTV state while required exit routes remain active.
    function testScheduledHighSeverity() public {
        _prepareFixedRateMarkets("reduce-ltv-high");
        _executeSeveritySchedule(BorrowMarketOffboardingSeverity.HIGH);
    }

    /// @dev Manifest: Critical severity with T0 set to the current time and all markets still carrying debt.
    /// Executes daily scheduled steps from T+1 through T+6 at 10%/20%/40%/80%/160%/320% APR floors, followed by the
    /// first terminal step at T+7 days. Verifies approved 3-point/5-point reductions, exact rate updates, ordered LTV
    /// thresholds, and preserved frozen/unpaused exit state after every Timelock execution.
    function testScheduledCriticalSeverity() public {
        _prepareFixedRateMarkets("reduce-ltv-critical");
        _executeSeveritySchedule(BorrowMarketOffboardingSeverity.CRITICAL);
    }

    /// @dev Manifest: five markets where one reports zero borrowed assets and shares while the other four retain debt.
    /// Executes the correction pair and verifies the cleared market is omitted and unchanged, while every outstanding
    /// market receives its configured rate and LTV reduction in manifest order.
    function testBatchBSkipsClearedMarketAndContinuesOutstandingMarkets() public {
        _prepareFixedRateMarkets("reduce-ltv-skip-cleared");
        vm.mockCall(
            borrowMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
        );
        LtvMarketSnapshot[] memory beforeState = _marketSnapshots();
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );

        assertEq(IMarket(borrowMarkets[0]).maxLtv(), beforeState[0].maxLtv, "cleared market LTV changed");
        for (uint256 i = 1; i < borrowMarkets.length; ++i) {
            _assertReduction(i, beforeState[i]);
        }
    }

    /// @dev Manifest: only one debt-bearing market, configured for a 5-point reduction after its three thresholds are set
    /// to 2%, 4%, and 8%. Executes the Timelock pair and verifies independent saturating subtraction produces 0%, 0%,
    /// and 3% rather than underflowing or applying one shared terminal value.
    function testBatchBSaturatesEachLtvThresholdIndependentlyAtZero() public {
        _prepareFixedRateMarkets("reduce-ltv-saturating");
        IMarket market = IMarket(borrowMarkets[0]);
        IDcfDlbPriorityLiquidationEngine liquidationEngine =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory configuration = liquidationEngine.liquidationConfiguration();
        configuration.maxLiquidationLtv = 0.04 ether;
        configuration.ltvForCompleteLiquidation = 0.08 ether;

        vm.startPrank(address(timelock));
        market.setMaxLtv(0.02 ether);
        liquidationEngine.setLiquidationConfiguration(configuration);
        vm.stopPrank();

        for (uint256 i = 1; i < borrowMarkets.length; ++i) {
            vm.mockCall(
                borrowMarkets[i], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
            );
        }
        manifest.markets[0].ltvReduction = 0.05 ether;
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );

        configuration = liquidationEngine.liquidationConfiguration();
        assertEq(market.maxLtv(), 0, "market LTV did not saturate");
        assertEq(configuration.maxLiquidationLtv, 0, "liquidation LTV did not saturate");
        assertEq(configuration.ltvForCompleteLiquidation, 0.03 ether, "complete-liquidation LTV reduced incorrectly");
    }

    /// @dev Manifest and borrower list are valid, but every configured market reports zero borrowed assets and shares.
    /// Runs the operational entrypoint and verifies it stops with `debt targets reached`, writing no schedule, execute,
    /// inputs, or simulation report; only the already-created borrower-list input remains.
    function testBatchBStopsOnlyWhenAllDebtTargetsAreReached() public {
        _prepareFixedRateMarkets("reduce-ltv-targets-reached");
        string memory manifestPath = _writeSimulationInputs("all-debt-targets-reached", type(uint128).max);
        BorrowMarketOffboardingManifest memory completedManifest =
            BorrowMarketOffboardingIO.loadActivationManifest(manifestPath);
        string memory outputDirectory = BorrowMarketOffboarding.artifactDirectory(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, completedManifest
        );
        for (uint256 i; i < borrowMarkets.length; ++i) {
            vm.mockCall(
                borrowMarkets[i], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
            );
        }

        vm.expectRevert(bytes("Batch B: debt targets reached"));
        scriptHarness.run(uint256(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);

        assertFalse(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_SCHEDULE_FILE)), "schedule written");
        assertFalse(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_EXECUTE_FILE)), "execute written");
        assertFalse(vm.exists(string.concat(outputDirectory, "/inputs.json")), "inputs written");
        assertFalse(vm.exists(string.concat(outputDirectory, "/simulation-report.json")), "report written");
        assertTrue(vm.exists(string.concat(outputDirectory, "/borrowers.json")), "borrower input missing");
    }

    /// @dev Manifest: scheduled step 1 is submitted one second before its severity-specific T0 offset becomes due.
    /// Verifies preparation rejects the early operation before generating an executable correction batch.
    function testBatchBRejectsScheduledStepBeforeItIsDue() public {
        _prepareFixedRateMarkets("reduce-ltv-early-step");
        vm.warp(manifest.t0 + 1 days - 1);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: scheduled step is not due");
    }

    /// @dev Manifest: every market's correction rate is one raw unit below the selected step's 10% APR floor.
    /// Verifies the schedule floor is enforced per market before any rate or LTV update is generated.
    function testBatchBRejectsRateBelowScheduleAprFloor() public {
        _prepareFixedRateMarkets("reduce-ltv-below-floor");
        uint256 belowFloor = 0.1 ether / uint256(365 days) - 1;
        for (uint256 i; i < manifest.markets.length; ++i) {
            manifest.markets[i].correctionRateSpy = belowFloor;
        }

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: rate below schedule APR floor");
    }

    /// @dev Manifest: one market's active fixed rate is raised one raw unit above its proposed correction rate.
    /// Verifies a correction cannot lower the live fixed rate even when the configured schedule floor is satisfied.
    function testBatchBRejectsRateBelowCurrentFixedRate() public {
        _prepareFixedRateMarkets("reduce-ltv-below-current");
        address irm = IMarket(borrowMarkets[0]).irm();
        uint256 targetRate = manifest.markets[0].correctionRateSpy;
        vm.prank(address(timelock));
        FixedRateIrm(irm).setBorrowRate(targetRate + 1);

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, "Batch B: rate below current rate");
    }

    /// @dev Manifest: terminal mode is six hours past the prior execution, but requests step 3 after completed step 1.
    /// Verifies missed hours do not permit catch-up or skipped steps; then requests the valid next step with a 10-point
    /// reduction and verifies the independent 5-point maximum is still enforced.
    function testTerminalStepRejectsCatchUp() public {
        _prepareFixedRateMarkets("reduce-ltv-terminal-catch-up");
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.TERMINAL;
        manifest.t0 = block.timestamp - 28 days;
        manifest.step = 3;
        manifest.lastExecutedStep = 1;
        manifest.lastStepExecutedAt = block.timestamp - 6 hours;

        vm.expectRevert("Batch B: steps must be sequential");
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, input);
        vm.stopBroadcast();

        manifest.step = 2;
        manifest.lastOperationId = bytes32(uint256(1));
        vm.mockCall(
            address(timelock),
            abi.encodeWithSignature("isOperationDone(bytes32)", manifest.lastOperationId),
            abi.encode(true)
        );
        for (uint256 i; i < manifest.markets.length; ++i) {
            manifest.markets[i].ltvReduction = 0.1 ether;
        }
        vm.expectRevert("Batch B: LTV reduction above maximum");
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, input);
    }

    /// @dev Manifest: terminal step 2 follows completed step 1, but is requested one second before the one-hour interval.
    /// Verifies terminal corrections cannot execute more than once per hour even when all other inputs are valid.
    function testTerminalStepRejectsSubHourlyExecution() public {
        _prepareFixedRateMarkets("reduce-ltv-terminal-hourly");
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.TERMINAL;
        manifest.t0 = block.timestamp - 28 days;
        manifest.step = 2;
        manifest.lastExecutedStep = 1;
        manifest.lastStepExecutedAt = block.timestamp - 1 hours + 1;

        vm.expectRevert("Batch B: terminal step interval not elapsed");
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, input);
    }

    /// @dev Manifest: Medium severity with the complete fork borrower inventory plus deterministic boundary positions.
    /// Executes all scheduled corrections, then sequential hourly terminal steps and ordinary liquidations after each
    /// update until every market reaches zero borrowed assets and shares. Only the liquidator is funded; borrowers are
    /// never funded or repaid directly. Verifies ordered thresholds and that correction stops immediately at zero debt.
    function testTerminalPathClearsForkDebtThroughOrdinaryLiquidations() public {
        _prepareFixedRateMarkets("reduce-ltv-terminal-liquidation");
        _executeSeveritySchedule(BorrowMarketOffboardingSeverity.MEDIUM);
        vm.clearMockedCalls();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            vm.mockCall(
                IMarket(borrowMarkets[i]).oracle(),
                abi.encodeCall(IOracle.getPrice, ()),
                abi.encode(fixtures[i].livePrice)
            );
        }

        uint256 terminalAt = manifest.t0 + 28 days;
        uint256 nextStepAt = manifest.lastStepExecutedAt + 1 hours;
        if (nextStepAt > terminalAt) terminalAt = nextStepAt;
        if (block.timestamp < terminalAt) vm.warp(terminalAt);
        _liquidateEligibleBorrowers();

        uint256 terminalSteps;
        while (!_allDebtCleared()) {
            require(terminalSteps++ < 24, "terminal test exceeded step bound");
            uint256 earliestNextStep = manifest.lastStepExecutedAt + 1 hours;
            if (block.timestamp < earliestNextStep) vm.warp(earliestNextStep);
            manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.TERMINAL;
            manifest.step = manifest.lastExecutedStep + 1;
            _setCorrectionInputs(0.8 ether / uint256(365 days), 0.05 ether);

            _executeSimulatedCorrection("terminal-ordinary-liquidation");
            _liquidateEligibleBorrowers();
        }

        for (uint256 i; i < borrowMarkets.length; ++i) {
            Balance memory debt = IMarket(borrowMarkets[i]).totalBorrowed();
            assertEq(debt.assets, 0, "terminal borrowed assets remain");
            assertEq(debt.shares, 0, "terminal borrowed shares remain");
            IMarket market = IMarket(borrowMarkets[i]);
            LiquidationConfiguration memory configuration =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
            assertLe(market.maxLtv(), configuration.maxLiquidationLtv, "terminal market threshold out of order");
            assertLe(
                configuration.maxLiquidationLtv,
                configuration.ltvForCompleteLiquidation,
                "terminal liquidation thresholds out of order"
            );
        }

        manifest.step = manifest.lastExecutedStep + 1;
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert("Batch B: debt targets reached");
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, manifest, input);
    }

    /// @dev Schedules the exact correction batch before invoking the operational simulation. Verifies the gate reuses a
    /// waiting operation by warping to its existing timestamp, then reuses the same operation again once it is ready. The
    /// simulated execution is reverted each time, leaving the real fork operation pending and its payload unchanged.
    function testBatchBSimulationReusesPendingAndReadyTimelockOperation() public {
        _prepareFixedRateMarkets("reduce-ltv-resimulation");
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        bytes32 operationId = _correctionOperationId();
        input = scriptHarness.runPhase(phase, manifest, input);
        _executeSafeBatch(phase, REDUCE_LTV_SCHEDULE_FILE, manifest.timelockSafe);

        assertTrue(timelock.isOperationPending(operationId), "operation was not scheduled");
        assertFalse(timelock.isOperationReady(operationId), "operation unexpectedly ready");

        string memory manifestPath = _writeSimulationInputs(manifest.activationId, type(uint128).max);
        scriptHarness.run(uint256(phase), manifestPath);

        assertTrue(timelock.isOperationPending(operationId), "pending operation was lost");
        assertFalse(timelock.isOperationReady(operationId), "simulation changed operation readiness");
        assertFalse(timelock.isOperationDone(operationId), "simulation executed the real operation");

        vm.warp(timelock.getTimestamp(operationId));
        assertTrue(timelock.isOperationReady(operationId), "operation did not become ready");
        scriptHarness.run(uint256(phase), manifestPath);

        assertTrue(timelock.isOperationPending(operationId), "ready operation was lost");
        assertTrue(timelock.isOperationReady(operationId), "ready operation changed state");
        assertFalse(timelock.isOperationDone(operationId), "simulation completed the real operation");
        string memory report = vm.readFile(
            string.concat(BorrowMarketOffboarding.artifactDirectory(phase, manifest), "/simulation-report.json")
        );
        assertEq(vm.parseJsonString(report, ".operationId"), vm.toString(operationId), "simulated payload changed");
    }

    /// @dev Manifest: complete borrower inputs with one approved limit set to zero and every other limit set permissively.
    /// Repeats the fork simulation for liquidation funding, bad debt, supplier loss, protocol loss, and per-Vault loss,
    /// after seeding artifacts from a previous passing run. Verifies the measured nonzero outcome exceeds the selected
    /// limit, produces the specific rejection, and removes every stale operational artifact.
    /// Confirms no schedule, execute, inputs, or report artifact is written after any failed simulation.
    function testBatchBSimulationRejectsEveryExceededLossLimitWithoutWritingArtifacts() public {
        _prepareFixedRateMarkets("reduce-ltv-loss-limits");
        vm.mockCall(
            IMarket(borrowMarkets[0]).oracle(),
            abi.encodeCall(IOracle.getPrice, ()),
            abi.encode(boundaryFixtures[0].price / 2)
        );
        _assertSimulationLimitFailure("simulation-funding-limit-isolated", 0, "Simulation: funding limit exceeded");
        _assertSimulationLimitFailure("simulation-bad-debt-limit-isolated", 1, "Simulation: bad debt limit exceeded");
        _assertSimulationLimitFailure(
            "simulation-supplier-loss-limit-isolated", 2, "Simulation: supplier loss limit exceeded"
        );
        _assertSimulationLimitFailure(
            "simulation-protocol-loss-limit-isolated", 3, "Simulation: protocol loss limit exceeded"
        );
        _assertSimulationLimitFailure(
            "simulation-vault-loss-limit-isolated", 4, "Simulation: Vault loss limit exceeded"
        );
    }

    /// @dev Manifest: complete borrower inputs and permissive limits, but one known borrower's liquidation is mocked to
    /// revert with an unexpected error. Verifies the gate bubbles that error and aborts instead of treating it as the
    /// permitted non-liquidatable/solvent result.
    function testBatchBSimulationAbortsOnUnexpectedLiquidationRevert() public {
        _prepareFixedRateMarkets("reduce-ltv-unexpected-revert");
        string memory simulationManifestPath =
            _writeSimulationInputs("simulation-gate-unexpected-revert", type(uint128).max);
        address borrower = _forkBorrowers(0)[0];
        bytes memory liquidationCall = abi.encodeCall(IMarketBase.liquidate, (borrower, bytes(""), bytes("")));
        bytes memory unexpectedError = abi.encodeWithSignature("Error(string)", "unexpected liquidation failure");
        vm.mockCallRevert(borrowMarkets[0], liquidationCall, unexpectedError);

        vm.expectRevert(unexpectedError);
        scriptHarness.run(uint256(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV), simulationManifestPath);
    }

    function _assertSimulationLimitFailure(string memory activationId, uint256 limitIndex, bytes memory expectedError)
        private
    {
        uint256[5] memory limits;
        for (uint256 i; i < limits.length; ++i) {
            limits[i] = type(uint128).max;
        }
        limits[limitIndex] = 0;
        string memory manifestPath = _writeSimulationInputs(activationId, limits);
        BorrowMarketOffboardingManifest memory simulationManifest =
            BorrowMarketOffboardingIO.loadActivationManifest(manifestPath);
        string memory outputDirectory = BorrowMarketOffboarding.artifactDirectory(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, simulationManifest
        );

        vm.writeFile(string.concat(outputDirectory, "/", REDUCE_LTV_SCHEDULE_FILE), "{}");
        vm.writeFile(string.concat(outputDirectory, "/", REDUCE_LTV_EXECUTE_FILE), "{}");
        vm.writeFile(string.concat(outputDirectory, "/inputs.json"), "{}");
        vm.writeFile(string.concat(outputDirectory, "/simulation-report.json"), '{"passed":true}');

        assertTrue(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_SCHEDULE_FILE)), "schedule fixture missing");
        assertTrue(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_EXECUTE_FILE)), "execute fixture missing");
        assertTrue(vm.exists(string.concat(outputDirectory, "/inputs.json")), "inputs fixture missing");
        assertTrue(vm.exists(string.concat(outputDirectory, "/simulation-report.json")), "report fixture missing");

        vm.expectRevert(expectedError);
        scriptHarness.run(uint256(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);

        assertFalse(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_SCHEDULE_FILE)), "failed schedule written");
        assertFalse(vm.exists(string.concat(outputDirectory, "/", REDUCE_LTV_EXECUTE_FILE)), "failed execute written");
        assertFalse(vm.exists(string.concat(outputDirectory, "/inputs.json")), "failed inputs written");
        assertFalse(vm.exists(string.concat(outputDirectory, "/simulation-report.json")), "failed report written");
        assertTrue(vm.exists(string.concat(outputDirectory, "/borrowers.json")), "borrower input missing");
    }

    function _executeSimulatedCorrection(string memory activationId) private {
        manifest.activationId = activationId;
        bytes32 operationId = _correctionOperationId();
        string memory manifestPath = _writeSimulationInputs(activationId, type(uint128).max);
        scriptHarness.run(uint256(BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV), manifestPath);
        _executeTimelockArtifacts(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );
        manifest.lastExecutedStep = manifest.step;
        manifest.lastStepExecutedAt = block.timestamp;
        manifest.lastOperationId = operationId;
    }

    function _liquidateEligibleBorrowers() private returns (uint256 liquidationCount) {
        address liquidator = makeAddr("terminal-liquidator");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            liquidationCount += _liquidateBorrowerList(market, _forkBorrowers(i), liquidator);

            address[] memory testBorrowers = new address[](3);
            testBorrowers[0] = fixtures[i].exitBorrower;
            testBorrowers[1] = fixtures[i].liquidationBorrower;
            testBorrowers[2] = boundaryFixtures[i].borrower;
            liquidationCount += _liquidateBorrowerList(market, testBorrowers, liquidator);
        }
    }

    function _executeSeveritySchedule(BorrowMarketOffboardingSeverity severity) private {
        manifest.severity = severity;
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.SCHEDULED;
        manifest.lastExecutedStep = 0;
        manifest.lastStepExecutedAt = 0;
        manifest.lastOperationId = bytes32(0);

        uint256 stepCount = severity == BorrowMarketOffboardingSeverity.CRITICAL ? 6 : 4;
        for (uint256 step = 1; step <= stepCount; ++step) {
            (uint256 offset, uint256 apr) = _scheduledStep(severity, step);
            uint256 dueAt = manifest.t0 + offset;
            if (block.timestamp < dueAt) vm.warp(dueAt);

            manifest.step = step;
            _setCorrectionInputs(apr / uint256(365 days), 0.05 ether);
            manifest.markets[0].ltvReduction = 0.03 ether;

            LtvMarketSnapshot[] memory beforeState = _marketSnapshots();
            _executeAndRecordCorrection();
            for (uint256 i; i < borrowMarkets.length; ++i) {
                _assertReduction(i, beforeState[i]);
            }
        }

        _executeFirstTerminalStep(severity);
        _assertAllFrozenAndUnpaused();
        _assertAllRequiredExitIntegrationsActive();
    }

    function _executeFirstTerminalStep(BorrowMarketOffboardingSeverity severity) private {
        uint256 terminalOffset = severity == BorrowMarketOffboardingSeverity.MEDIUM
            ? 28 days
            : severity == BorrowMarketOffboardingSeverity.HIGH ? 14 days : 7 days;
        uint256 executeAt = manifest.t0 + terminalOffset;
        uint256 hourlyAt = manifest.lastStepExecutedAt + 1 hours;
        if (hourlyAt > executeAt) executeAt = hourlyAt;
        if (block.timestamp < executeAt) vm.warp(executeAt);

        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.TERMINAL;
        manifest.step = manifest.lastExecutedStep + 1;
        uint256 terminalApr = severity == BorrowMarketOffboardingSeverity.CRITICAL ? 3.2 ether : 0.8 ether;
        _setCorrectionInputs(terminalApr / uint256(365 days), 0.05 ether);
        manifest.markets[0].ltvReduction = 0.03 ether;

        LtvMarketSnapshot[] memory beforeState = _marketSnapshots();
        _executeAndRecordCorrection();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertReduction(i, beforeState[i]);
        }
    }

    function _scheduledStep(BorrowMarketOffboardingSeverity severity, uint256 step)
        private
        pure
        returns (uint256 offset, uint256 apr)
    {
        if (severity == BorrowMarketOffboardingSeverity.MEDIUM) {
            if (step == 1) return (1 days, 0.1 ether);
            if (step == 2) return (7 days, 0.2 ether);
            if (step == 3) return (14 days, 0.4 ether);
            return (21 days, 0.8 ether);
        }
        if (severity == BorrowMarketOffboardingSeverity.HIGH) {
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

    function _severityName(BorrowMarketOffboardingSeverity severity) private pure returns (string memory) {
        if (severity == BorrowMarketOffboardingSeverity.MEDIUM) return "medium";
        if (severity == BorrowMarketOffboardingSeverity.HIGH) return "high";
        return "critical";
    }

    function _marketSnapshots() private view returns (LtvMarketSnapshot[] memory snapshots) {
        snapshots = new LtvMarketSnapshot[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            address liquidationEngine = market.liquidationEngine();
            snapshots[i] = LtvMarketSnapshot({
                irm: market.irm(),
                liquidationEngine: liquidationEngine,
                maxLtv: market.maxLtv(),
                liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration()
            });
        }
    }

    function _assertReduction(uint256 marketIndex, LtvMarketSnapshot memory beforeState) private view {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        LiquidationConfiguration memory afterConfig =
            IDcfDlbPriorityLiquidationEngine(beforeState.liquidationEngine).liquidationConfiguration();
        uint256 reduction = manifest.markets[marketIndex].ltvReduction;

        assertEq(market.irm(), beforeState.irm, "IRM address changed");
        assertEq(market.liquidationEngine(), beforeState.liquidationEngine, "liquidation engine changed");
        assertEq(market.maxLtv(), _saturatingSub(beforeState.maxLtv, reduction), "wrong market max LTV");
        assertEq(
            afterConfig.maxLiquidationLtv,
            _saturatingSub(beforeState.liquidationConfiguration.maxLiquidationLtv, reduction),
            "wrong maximum liquidation LTV"
        );
        assertEq(
            afterConfig.ltvForCompleteLiquidation,
            _saturatingSub(beforeState.liquidationConfiguration.ltvForCompleteLiquidation, reduction),
            "wrong complete-liquidation LTV"
        );
        (uint256 borrowRate,) = FixedRateIrm(beforeState.irm).irState();
        assertEq(borrowRate, manifest.markets[marketIndex].correctionRateSpy, "wrong corrected fixed rate");
        _assertValidConfiguration(market, afterConfig);
        _assertUnscheduledFieldsUnchanged(beforeState.liquidationConfiguration, afterConfig);
        _assertFrozenAndUnpaused(market);
    }

    function _saturatingSub(uint256 value, uint256 reduction) private pure returns (uint256) {
        return value > reduction ? value - reduction : 0;
    }

    function _writeSimulationInputs(string memory activationId, uint256 limit)
        private
        returns (string memory simulationManifestPath)
    {
        uint256[5] memory limits;
        for (uint256 i; i < limits.length; ++i) {
            limits[i] = limit;
        }
        return _writeSimulationInputs(activationId, limits);
    }

    function _writeSimulationInputs(string memory activationId, uint256[5] memory limits)
        private
        returns (string memory simulationManifestPath)
    {
        simulationManifestPath = string.concat("ERP/ERP-OFFBOARD-02/output/", activationId, "-manifest.json");
        _writeSimulationManifest(simulationManifestPath, activationId, limits);

        BorrowMarketOffboardingManifest memory simulationManifest = manifest;
        simulationManifest.activationId = activationId;
        string memory outputDirectory = BorrowMarketOffboarding.artifactDirectory(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, simulationManifest
        );
        vm.createDir(outputDirectory, true);
        _writeSimulationBorrowers(string.concat(outputDirectory, "/borrowers.json"));
    }

    function _writeSimulationManifest(string memory path, string memory activationId, uint256[5] memory limits)
        private
    {
        vm.writeFile(path, vm.readFile(MANIFEST_FILE));
        vm.writeJson(string.concat('"', activationId, '"'), path, ".activationId");
        vm.writeJson(vm.toString(uint256(manifest.severity)), path, ".severity");
        vm.writeJson(vm.toString(uint256(manifest.schedulePhase)), path, ".schedulePhase");
        vm.writeJson(vm.toString(manifest.t0), path, ".t0");
        vm.writeJson(vm.toString(manifest.step), path, ".step");
        vm.writeJson(vm.toString(manifest.lastExecutedStep), path, ".lastExecutedStep");
        vm.writeJson(vm.toString(manifest.lastStepExecutedAt), path, ".lastStepExecutedAt");
        vm.writeJson(string.concat('"', vm.toString(manifest.lastOperationId), '"'), path, ".lastOperationId");
        vm.writeJson(vm.toString(manifest.sourceBlock), path, ".sourceBlock");
        vm.writeJson(_simulationMarketsJson(limits), path, ".markets");
        vm.writeJson(_simulationVaultsJson(limits[4]), path, ".vaults");
    }

    function _simulationMarketsJson(uint256[5] memory limits) private view returns (string memory json) {
        for (uint256 i; i < manifest.markets.length; ++i) {
            BorrowMarketOffboardingMarket memory market = manifest.markets[i];
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                '{"market":"',
                vm.toString(market.market),
                '","leverage":"',
                vm.toString(market.leverage),
                '","fixedRateSpy":',
                vm.toString(market.fixedRateSpy),
                ',"correctionRateSpy":',
                vm.toString(market.correctionRateSpy),
                ',"ltvReduction":',
                vm.toString(market.ltvReduction),
                ',"maxLiquidationFundingAssets":',
                vm.toString(limits[0]),
                ',"maxBadDebtAssets":',
                vm.toString(limits[1]),
                ',"maxSupplierLossAssets":',
                vm.toString(limits[2]),
                ',"maxProtocolLossAssets":',
                vm.toString(limits[3]),
                "}"
            );
        }
        return string.concat("[", json, "]");
    }

    function _simulationVaultsJson(uint256 maxVaultLossAssets) private view returns (string memory json) {
        for (uint256 i; i < manifest.vaults.length; ++i) {
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                '{"vault":"',
                vm.toString(manifest.vaults[i].vault),
                '","allocator":"',
                vm.toString(manifest.vaults[i].allocator),
                '","maxVaultLossAssets":',
                vm.toString(maxVaultLossAssets),
                ',"reallocationBufferAssets":',
                vm.toString(manifest.vaults[i].reallocationBufferAssets),
                ',"replacementMarkets":[]',
                "}"
            );
        }
        return string.concat("[", json, "]");
    }

    function _writeSimulationBorrowers(string memory path) private {
        string memory marketsJson;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            address[] memory currentBorrowers = _forkBorrowers(i);
            string memory borrowersJson;
            for (uint256 j; j < currentBorrowers.length; ++j) {
                borrowersJson =
                    string.concat(borrowersJson, j == 0 ? "" : ",", '"', vm.toString(currentBorrowers[j]), '"');
            }
            borrowersJson = string.concat(
                borrowersJson,
                ',"',
                vm.toString(fixtures[i].exitBorrower),
                '","',
                vm.toString(fixtures[i].liquidationBorrower),
                '","',
                vm.toString(boundaryFixtures[i].borrower),
                '"'
            );
            marketsJson = string.concat(
                marketsJson,
                i == 0 ? "" : ",",
                '{"borrowers":[',
                borrowersJson,
                '],"market":"',
                vm.toString(borrowMarkets[i]),
                '"}'
            );
        }

        vm.writeFile(
            path,
            string.concat(
                '{"chainId":',
                vm.toString(block.chainid),
                ',"markets":[',
                marketsJson,
                '],"sourceBlock":',
                vm.toString(manifest.sourceBlock),
                ',"subgraphUrl":"test"}'
            )
        );
    }

    function _assertMarketReductionAndRoutes(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        _assertReduction(marketIndex, ltvSnapshots[marketIndex]);
        _liquidateBoundaryPosition(marketIndex);
        _exerciseExitAndLiquidationRoutes(market, fixtures[marketIndex]);
        _assertFrozenAndUnpaused(market);
    }

    function _seedBoundaryPositions() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            uint256 collateralAssets = 10 ** uint256(IERC20Metadata(market.collateralToken()).decimals()) / 100;
            uint256 collateralValue =
                Math.mulDiv(collateralAssets, fixtures[i].livePrice, LENDING_ORACLE_PRICE_PRECISION);
            uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);
            uint256 targetDebt = maximumBorrow - maximumBorrow / 1_000_000;
            uint256 borrowAssets = Math.mulDiv(targetDebt, 1 ether, 1 ether + market.borrowOpeningFee()) - 1;
            address borrower = makeAddr(string.concat("boundary-borrower-", vm.toString(i)));

            IERC20 borrowToken = IERC20(market.borrowToken());
            address supplier = makeAddr(string.concat("boundary-supplier-", vm.toString(i)));
            deal(address(borrowToken), supplier, maximumBorrow);
            vm.startPrank(supplier);
            borrowToken.approve(address(market), maximumBorrow);
            market.addSupply(maximumBorrow, 0, supplier);
            vm.stopPrank();

            _openBorrowPosition(market, borrower, collateralAssets, borrowAssets);
            address liquidator = makeAddr(string.concat("boundary-liquidator-", vm.toString(i)));
            uint256 maxLiquidationLtv =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .liquidationConfiguration()
            .maxLiquidationLtv;
            uint256 targetLtv = maxLiquidationLtv - manifest.markets[i].ltvReduction / 2;
            boundaryFixtures.push();
            boundaryFixtures[i].borrower = borrower;
            boundaryFixtures[i].liquidator = liquidator;
            boundaryFixtures[i].price = Math.mulDiv(fixtures[i].livePrice, market.maxLtv(), targetLtv);
        }
    }

    function _assertHealthyAndSnapshot(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address liquidationEngine = market.liquidationEngine();
        vm.mockCall(
            market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(boundaryFixtures[marketIndex].price)
        );

        IERC20 borrowToken = IERC20(market.borrowToken());
        address liquidator = boundaryFixtures[marketIndex].liquidator;
        deal(address(borrowToken), liquidator, 1_000_000 ether);
        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (bool liquidated, bytes memory returnData) = address(market)
            .call(abi.encodeCall(IMarketBase.liquidate, (boundaryFixtures[marketIndex].borrower, bytes(""), bytes(""))));
        vm.stopPrank();

        assertFalse(liquidated, "boundary position liquidatable before LTV reduction");
        assertEq(
            returnData,
            abi.encodeWithSelector(
                IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition
                .selector
            ),
            "unexpected pre-reduction liquidation revert"
        );

        ltvSnapshots.push(
            LtvMarketSnapshot({
                irm: market.irm(),
                liquidationEngine: liquidationEngine,
                maxLtv: market.maxLtv(),
                liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration()
            })
        );
    }

    function _liquidateBoundaryPosition(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address borrower = boundaryFixtures[marketIndex].borrower;
        address liquidator = boundaryFixtures[marketIndex].liquidator;
        vm.mockCall(
            market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(boundaryFixtures[marketIndex].price)
        );

        Position memory beforePosition = market.position(borrower);
        IERC20 borrowToken = IERC20(market.borrowToken());
        deal(address(borrowToken), liquidator, 1_000_000 ether);
        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (uint256 seizedCollateral, uint256 repaidBorrow,) = market.liquidate(borrower, "", "");
        vm.stopPrank();

        Position memory afterPosition = market.position(borrower);
        assertGt(seizedCollateral, 0, "newly liquidatable position seized no collateral");
        assertGt(repaidBorrow, 0, "newly liquidatable position repaid no debt");
        assertLt(afterPosition.borrowShares, beforePosition.borrowShares, "boundary debt was not reduced");
        assertLt(afterPosition.collateralAssets, beforePosition.collateralAssets, "boundary collateral was not seized");
    }

    function _assertValidConfiguration(IMarket market, LiquidationConfiguration memory config) private view {
        assertLe(market.maxLtv(), config.maxLiquidationLtv, "market/liquidation LTV order invalid");
        assertLe(config.maxLiquidationLtv, config.ltvForCompleteLiquidation, "liquidation/complete LTV order invalid");
        assertLe(config.ltvForCompleteLiquidation, 1 ether, "complete-liquidation LTV above 100%");
        assertGt(config.dynamicBonusFeeDecaySteepness, 0, "zero bonus decay steepness");
        assertLe(config.dynamicBonusFeeDecaySteepness, 100 ether, "bonus decay steepness too high");

        uint256 totalLiquidationFee = config.dynamicBonusFeeStart + config.liquidationBaseFee;
        assertLe(totalLiquidationFee, 0.15 ether, "liquidation fee above maximum");
        assertLe(totalLiquidationFee, 1 ether - config.maxLiquidationLtv, "fee incompatible with liquidation LTV");
        assertLe(config.minPenaltyPercentage, 1 ether, "minimum penalty above 100%");
        assertLe(config.protocolFeePercentage, 1 ether, "protocol fee above 100%");
        if (config.protocolFeePercentage != 0) assertNotEq(market.feeRecipient(), address(0), "zero fee recipient");
        assertLe(config.priorityLiquidationGracePeriod, 1 hours, "priority grace period too long");
        assertLe(config.taggerLiquidationGracePeriod, 30 minutes, "tagger grace period too long");
        assertLe(config.liquidationWindowTag, 3 days, "liquidation window too long");
        assertLe(
            config.priorityLiquidationGracePeriod + config.taggerLiquidationGracePeriod,
            config.liquidationWindowTag,
            "grace periods exceed liquidation window"
        );
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
            afterConfig.isEnabledPriorityLiquidation,
            beforeConfig.isEnabledPriorityLiquidation,
            "priority liquidation flag changed"
        );
        assertEq(
            afterConfig.disablePriorityLiquidationAbovePositionLtv,
            beforeConfig.disablePriorityLiquidationAbovePositionLtv,
            "priority-liquidation cutoff changed"
        );
        assertEq(
            afterConfig.priorityLiquidationGracePeriod,
            beforeConfig.priorityLiquidationGracePeriod,
            "priority grace period changed"
        );
        assertEq(
            afterConfig.taggerLiquidationGracePeriod,
            beforeConfig.taggerLiquidationGracePeriod,
            "tagger grace period changed"
        );
        assertEq(afterConfig.liquidationWindowTag, beforeConfig.liquidationWindowTag, "liquidation window changed");
    }
}
