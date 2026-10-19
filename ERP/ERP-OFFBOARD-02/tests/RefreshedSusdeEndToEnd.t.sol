// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingIO} from "../libraries/BorrowMarketOffboardingIO.sol";
import {
    BorrowMarketOffboardingMarket,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingSchedulePhase,
    BorrowMarketOffboardingSeverity
} from "../IBorrowMarketOffboarding.sol";

import {Balance, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {MarketConfig} from "@alto/lending/libraries/PendingLib.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";

/// @notice Notion ERP-OFFBOARD-02 Section 6 development pre-simulation. Executes the complete Medium severity response
/// against the live refreshed sUSDe borrow market and the DUSD Vault at a recent block: Batch A containment with a
/// liquidity-limited reallocation, the fixed-rate IRM, every scheduled and terminal Batch B correction through the
/// operational phase 2 gate, debt clearance through ordinary liquidations only, the phase 0 rerun that exits the Vault
/// completely, and Batch C recovery. Refresh the manifest and borrower fixtures with `scripts/fetch-borrowers.ts` when
/// the source block changes.
contract RefreshedSusdeEndToEndTest is BorrowMarketOffboardingTestBase {
    using AltoBalancesLib for address;

    address internal constant SUSDE_BORROW_MARKET = 0x5d8fA5E1fAcb746179BD1AEb3aA78Db384C52001;
    uint256 internal constant SUSDE_FORK_BLOCK = 26_225_900;

    uint256 internal correctionCount;
    uint256 internal liquidationCount;

    function _forkBlock() internal pure override returns (uint256) {
        return SUSDE_FORK_BLOCK;
    }

    function _manifestFile() internal pure override returns (string memory) {
        return "ERP/ERP-OFFBOARD-02/tests/fixtures/manifest-susde-26225900.json";
    }

    function _borrowerFixture() internal pure override returns (string memory) {
        return "ERP/ERP-OFFBOARD-02/tests/fixtures/borrowers-susde-26225900.json";
    }

    function setUp() public {
        _setUpManifest();
    }

    function testMediumSeverityOffboardingOfRefreshedSusdeMarket() public {
        assertEq(borrowMarkets.length, 1, "pre-simulation targets one market");
        assertEq(borrowMarkets[0], SUSDE_BORROW_MARKET, "unexpected target market");
        IMarket target = IMarket(SUSDE_BORROW_MARKET);
        _assertBorrowerListComplete(0);

        Balance memory debtBefore = target.totalBorrowed();
        uint256 vaultSupplyBefore = SUSDE_BORROW_MARKET.expectedSupplyAssets(address(vault));
        uint256 vaultSharesBefore = vaultToken.totalSupply();
        uint256 supplyQueueBefore = vault.supplyQueueLength();
        address originalIrm = target.irm();
        uint256 maxLtvBefore = target.maxLtv();
        assertGt(debtBefore.assets, 0, "live market has no debt to off-board");
        assertGt(vaultSupplyBefore, 0, "live Vault has no exposure to the market");
        assertTrue(_isInSupplyQueue(SUSDE_BORROW_MARKET), "live market is not in the supply queue");
        assertFalse(target.paused(FROZEN_TYPE), "live market is already frozen");
        emit log_named_decimal_uint("live market debt (DUSD)", debtBefore.assets, 18);
        emit log_named_decimal_uint("live Vault supply in market (DUSD)", vaultSupplyBefore, 18);
        emit log_named_uint("live borrowers", _forkBorrowers(0).length);

        // Batch A: freeze, zero cap, drop from the supply queue, reallocate the liquid part into the replacement.
        manifest.t0 = block.timestamp + 7 days;
        _executeBatchA();
        _assertAllFrozenAndUnpaused();
        _assertAllRequiredExitIntegrationsActive();
        assertFalse(_isInSupplyQueue(SUSDE_BORROW_MARKET), "market remains in supply queue");
        assertTrue(_isInWithdrawQueue(SUSDE_BORROW_MARKET), "market left the withdraw queue");
        assertEq(vault.supplyQueueLength(), supplyQueueBefore - 1, "unaffected supply queue entries changed");
        assertEq(vault.config(SUSDE_BORROW_MARKET).cap, 0, "Vault cap not zeroed");
        uint256 retainedAfterBatchA = SUSDE_BORROW_MARKET.expectedSupplyAssets(address(vault));
        assertLt(retainedAfterBatchA, vaultSupplyBefore, "Batch A reallocated nothing");
        assertGt(retainedAfterBatchA, 0, "Batch A withdrew illiquid exposure");
        emit log_named_decimal_uint("Vault supply retained after Batch A (DUSD)", retainedAfterBatchA, 18);

        // Batch B: dedicated fixed-rate IRM, then gated corrections until the market has no debt.
        _advanceTo(manifest.t0);
        _executeFixedRatePhase();
        assertNotEq(target.irm(), originalIrm, "fixed-rate IRM not attached");
        _executeGatedMediumCorrectionsToZero();
        assertTrue(_allDebtCleared(), "ordinary liquidations did not clear the debt");
        assertLt(target.maxLtv(), maxLtvBefore, "market LTV not reduced");
        _assertAllFrozenAndUnpaused();
        emit log_named_uint("gated corrections executed", correctionCount);
        emit log_named_uint("ordinary liquidations executed", liquidationCount);

        // Phase 0 rerun: with zero debt nothing accrues, so the generated plan exits the Vault completely.
        _executeConfiguredBatchA();
        assertEq(target.position(address(vault)).supplyShares, 0, "Vault market supply remains after phase 0 rerun");

        // Batch C: allocator withdraw-queue update, then the final Timelock batch.
        _executeRecoveryAllocatorPlans();
        assertFalse(_isInWithdrawQueue(SUSDE_BORROW_MARKET), "market remains in withdraw queue");
        _executeTimelockPhase(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);
        _assertRecoveryRoutesRemoved(0);
        MarketConfig memory config = vault.config(SUSDE_BORROW_MARKET);
        assertFalse(config.enabled, "Vault market remains enabled");
        assertEq(config.cap, 0, "Vault cap remains");
        assertEq(vault.quarantinedAssets(SUSDE_BORROW_MARKET), 0, "Vault quarantined assets");
        assertEq(vault.lostAssets(), 0, "Vault realized a loss");
        assertEq(vaultToken.totalSupply(), vaultSharesBefore, "Vault share supply changed");
        Balance memory debtAfter = target.totalBorrowed();
        assertEq(debtAfter.assets, 0, "debt assets remain");
        assertEq(debtAfter.shares, 0, "debt shares remain");

        // A completed recovery rerun is a no-op.
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, manifest, input);
        assertFalse(vm.exists(_artifactPath(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE)));
        assertFalse(vm.exists(_artifactPath(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_EXECUTE_FILE)));
        emit log_named_uint("debt cleared (days after t0)", (manifest.lastStepExecutedAt - manifest.t0) / 1 days);
    }

    /// @dev Mirrors the Medium schedule used by the suite but runs every correction through the operational phase 2
    /// gate: the borrower list is written where the script expects it, the activation manifest is written to disk, and
    /// `run()` simulates the exact Timelock batch before writing the schedule and execute artifacts.
    function _executeGatedMediumCorrectionsToZero() private {
        manifest.severity = BorrowMarketOffboardingSeverity.MEDIUM;
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.SCHEDULED;
        manifest.lastExecutedStep = 0;
        manifest.lastStepExecutedAt = 0;
        manifest.lastOperationId = bytes32(0);
        vm.mockCall(
            IMarket(SUSDE_BORROW_MARKET).oracle(),
            abi.encodeCall(IOracle.getPrice, ()),
            abi.encode(initialOraclePrices[0])
        );

        address liquidator = makeAddr("susde-terminal-liquidator");
        uint256[4] memory offsets = [uint256(1 days), 7 days, 14 days, 21 days];
        uint256[4] memory aprs = [uint256(0.1 ether), 0.2 ether, 0.4 ether, 0.8 ether];
        for (uint256 i; i < offsets.length && !_allDebtCleared(); ++i) {
            _advanceTo(manifest.t0 + offsets[i]);
            manifest.step = i + 1;
            _setCorrectionInputs(aprs[i] / uint256(365 days), 0.05 ether);
            _executeGatedCorrection();
            liquidationCount += _liquidateManifestBorrowers(liquidator);
        }
        if (_allDebtCleared()) return;

        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.TERMINAL;
        _advanceTo(manifest.t0 + 28 days);
        liquidationCount += _liquidateManifestBorrowers(liquidator);

        uint256 terminalSteps;
        while (!_allDebtCleared()) {
            require(terminalSteps++ < 24, "terminal step bound exceeded");
            _advanceTo(manifest.lastStepExecutedAt + 1 hours);
            manifest.step = manifest.lastExecutedStep + 1;
            _setCorrectionInputs(0.8 ether / uint256(365 days), 0.05 ether);
            _executeGatedCorrection();
            liquidationCount += _liquidateManifestBorrowers(liquidator);
        }
    }

    function _executeGatedCorrection() private {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        bytes32 operationId = _correctionOperationId();
        string memory manifestPath = _writeActivationManifest();
        _writeBorrowerArtifact();

        scriptHarness.run(uint256(phase), manifestPath);

        string memory outputDirectory = BorrowMarketOffboarding.artifactDirectory(phase, manifest);
        string memory report = vm.readFile(string.concat(outputDirectory, "/simulation-report.json"));
        assertEq(vm.parseJsonString(report, ".operationId"), vm.toString(operationId), "gate simulated another batch");
        _executeTimelockArtifacts(phase, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE);
        manifest.lastExecutedStep = manifest.step;
        manifest.lastStepExecutedAt = block.timestamp;
        manifest.lastOperationId = operationId;
        ++correctionCount;
    }

    function _writeActivationManifest() private returns (string memory path) {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        string memory outputDirectory = BorrowMarketOffboarding.artifactDirectory(phase, manifest);
        vm.createDir(outputDirectory, true);
        path = string.concat(outputDirectory, "/activation-manifest.json");
        vm.writeFile(path, vm.readFile(_manifestFile()));
        vm.writeJson(string.concat('"', manifest.activationId, '"'), path, ".activationId");
        vm.writeJson(vm.toString(uint256(manifest.severity)), path, ".severity");
        vm.writeJson(vm.toString(uint256(manifest.schedulePhase)), path, ".schedulePhase");
        vm.writeJson(vm.toString(manifest.t0), path, ".t0");
        vm.writeJson(vm.toString(manifest.step), path, ".step");
        vm.writeJson(vm.toString(manifest.lastExecutedStep), path, ".lastExecutedStep");
        vm.writeJson(vm.toString(manifest.lastStepExecutedAt), path, ".lastStepExecutedAt");
        vm.writeJson(string.concat('"', vm.toString(manifest.lastOperationId), '"'), path, ".lastOperationId");
        vm.writeJson(vm.toString(manifest.sourceBlock), path, ".sourceBlock");
        vm.writeJson(_marketsJson(), path, ".markets");
    }

    function _marketsJson() private view returns (string memory json) {
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
                vm.toString(market.maxLiquidationFundingAssets),
                ',"maxBadDebtAssets":',
                vm.toString(market.maxBadDebtAssets),
                ',"maxSupplierLossAssets":',
                vm.toString(market.maxSupplierLossAssets),
                ',"maxProtocolLossAssets":',
                vm.toString(market.maxProtocolLossAssets),
                "}"
            );
        }
        return string.concat("[", json, "]");
    }

    function _writeBorrowerArtifact() private {
        address[] memory borrowers = _forkBorrowers(0);
        string memory borrowersJson;
        for (uint256 i; i < borrowers.length; ++i) {
            borrowersJson = string.concat(borrowersJson, i == 0 ? "" : ",", '"', vm.toString(borrowers[i]), '"');
        }
        string memory path = BorrowMarketOffboardingIO.borrowerListPath(manifest);
        vm.writeFile(
            path,
            string.concat(
                '{"chainId":1,"markets":[{"borrowers":[',
                borrowersJson,
                '],"market":"',
                vm.toString(SUSDE_BORROW_MARKET),
                '"}],"sourceBlock":',
                vm.toString(manifest.sourceBlock),
                ',"subgraphUrl":"test-fixture"}'
            )
        );
    }
}
