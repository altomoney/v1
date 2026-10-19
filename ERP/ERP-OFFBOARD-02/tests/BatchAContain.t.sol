// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {
    BorrowMarketOffboardingMarket,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingVault
} from "../IBorrowMarketOffboarding.sol";

import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoVault} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchAContainTest is BorrowMarketOffboardingTestBase {
    struct ReallocationBufferState {
        address replacement;
        uint256 replacementBefore;
        uint256 replacementCap;
        uint256 sourceBefore;
        uint256 sourceTokenLiquidity;
        uint256 sourceWithdrawable;
        uint256 sourceTarget;
        uint256 replacementPrice;
    }

    using AltoBalancesLib for address;

    function setUp() public {
        _setUpManifest();
        assertEq(block.number, FORK_BLOCK, "wrong fork block");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertFalse(IMarketBase(borrowMarkets[i]).paused(FROZEN_TYPE), "market initially frozen");
            assertFalse(IMarketBase(borrowMarkets[i]).paused(PAUSE_TYPE), "market initially paused");
        }
        _assertAllRequiredExitIntegrationsActive();
    }

    /// @dev Manifest: five affected markets and one production Vault. Four markets are active and one is pre-frozen.
    /// Seeds supply, borrow, collateral, and liquidation positions, then executes every generated Batch A artifact.
    /// Verifies idempotent reruns, frozen/unpaused markets, cleared Vault work, blocked entry actions, correct queue state,
    /// and that repayment, withdrawals, liquidation, oracle, adapter, and other required exit routes remain available.
    function testBatchACompleteContainmentFromMixedCurrentState() public {
        manifest.activationId = "batch-a-complete-containment";
        _seedStandardPositions();
        vm.prank(manifest.freezerSafe);
        IPausable(borrowMarkets[borrowMarkets.length - 1]).pause(FROZEN_TYPE, true);
        assertFalse(IMarketBase(borrowMarkets[0]).paused(FROZEN_TYPE), "active market unexpectedly frozen");
        assertTrue(
            IMarketBase(borrowMarkets[borrowMarkets.length - 1]).paused(FROZEN_TYPE), "mixed-state market not frozen"
        );
        _executeBatchA();

        // A rerun removes the stale allocator plan when no more affected assets are currently withdrawable.
        uint256 remainingAssets = _affectedVaultSupplyAssets();
        string memory allocatorPath = _writeStaleBatchAAllocatorPlan(address(vault));
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, manifest, input);
        assertFalse(vm.exists(allocatorPath), "stale allocator plan");
        assertEq(_affectedVaultSupplyAssets(), remainingAssets, "zero-liquidity rerun changed exposure");

        assertGt(remainingAssets, 0, "illiquid Vault exposure was not retained");
        assertGt(
            manifest.vaults[0].replacementMarkets[0].expectedSupplyAssets(address(vault)),
            0,
            "withdrawable Vault assets were not reallocated"
        );

        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            _assertFrozenAndUnpaused(market);
            _assertVaultContainmentBeforeReallocation(address(market));
            assertGt(IOracle(market.oracle()).getPrice(), 0, "oracle unavailable after containment");
            _assertEntrancesBlocked(market, fixtures[i].exitBorrower);
            _exerciseExitAndLiquidationRoutes(market, fixtures[i]);
            _assertFrozenAndUnpaused(market);
            _assertRequiredExitIntegrationsActive(i);
        }
    }

    /// @dev Manifest: five affected markets and one production Vault with nonzero exposure to the affected markets.
    /// After containment, deploys a real destination market and adds enough liquidity for the Vault to withdraw fully.
    /// Executes a nonempty reallocation from every affected market into the destination, then verifies zero affected
    /// shares/quarantine, no material Vault loss, increased destination shares, and destination-only future allocation.
    function testBatchAReallocatesVaultToRealReplacementMarket() public {
        manifest.activationId = "batch-a-real-reallocation";
        uint256 affectedAssets = _affectedVaultSupplyAssets();
        assertGt(affectedAssets, 0, "test requires affected Vault supply");
        address replacement = _deployAndApproveReplacementBorrowMarket(affectedAssets + 10 ether);
        manifest.vaults[0].replacementMarkets.push(replacement);
        _provideAffectedMarketExitLiquidity();

        uint256 vaultAssetsBefore = vaultToken.totalAssets();
        uint256 replacementSharesBefore = IMarket(replacement).position(address(vault)).supplyShares;
        _executeBatchA();

        for (uint256 i; i < borrowMarkets.length; ++i) {
            address market = borrowMarkets[i];
            assertEq(
                IMarket(market).position(address(vault)).supplyShares, 0, "Vault supply remains in affected market"
            );
            assertEq(vault.quarantinedAssets(market), 0, "affected assets were quarantined");
            assertTrue(_isInWithdrawQueue(market), "affected market removed from withdraw queue");
            assertFalse(_isInSupplyQueue(market), "affected market remains in supply queue");
        }
        assertGt(
            IMarket(replacement).position(address(vault)).supplyShares,
            replacementSharesBefore,
            "replacement received no Vault supply"
        );
        assertGe(vaultToken.totalAssets() + 10, vaultAssetsBefore, "Vault lost assets during reallocation");

        // With no affected supply shares and no remaining queue update, rerunning removes the optional stale plan.
        string memory allocatorPath = _writeStaleBatchAAllocatorPlan(address(vault));
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, manifest, input);
        assertFalse(vm.exists(allocatorPath), "stale Batch A allocator plan remains");

        _depositAndAssertReplacementOnly(replacement);
    }

    /// @dev Manifest: five markets and one Vault, with a pending cap increase on one market and a pending removal on a
    /// different zero-cap market. Executes Batch A and verifies the curator artifact revokes both pending actions,
    /// leaves every cap at zero, and freezes every market without enabling the full pause.
    function testBatchARevokesPendingCapAndZeroCapPendingRemoval() public {
        manifest.activationId = "batch-a-pending-actions";
        address curator = vault.curator();
        address pendingCapMarket = borrowMarkets[0];
        address pendingRemovalMarket = borrowMarkets[2];

        uint256 increasedCap = uint256(vault.config(pendingCapMarket).cap) + 1;
        vm.prank(curator);
        vault.submitCap(pendingCapMarket, increasedCap);
        assertGt(vault.pendingCap(pendingCapMarket).validAt, 0, "pending cap not created");

        if (vault.config(pendingRemovalMarket).cap != 0) {
            vm.prank(curator);
            vault.submitCap(pendingRemovalMarket, 0);
        }
        assertEq(vault.config(pendingRemovalMarket).cap, 0, "removal fixture market cap is non-zero");
        vm.prank(curator);
        vault.submitMarketRemoval(pendingRemovalMarket);
        assertGt(vault.config(pendingRemovalMarket).removableAt, 0, "pending removal not created");

        _executeBatchA();

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertFrozenAndUnpaused(IMarketBase(borrowMarkets[i]));
            _assertVaultPendingWorkCleared(vault, borrowMarkets[i]);
        }
    }

    /// @dev Manifest: five affected markets and one production Vault, with one market already fully paused.
    /// Verifies Batch A rejects this state before containment because the ERP requires markets to remain unpaused while
    /// only the freeze blocks new entry actions.
    function testBatchARejectsPausedMarket() public {
        manifest.activationId = "batch-a-paused-rejection";
        vm.prank(manifest.freezerSafe);
        IPausable(borrowMarkets[0]).pause(PAUSE_TYPE, true);

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: market paused");
    }

    /// @dev Manifest: five affected markets and one production Vault whose configured allocator is not authorized.
    /// Verifies generation rejects the invalid Vault entry instead of writing a queue plan that the declared caller
    /// cannot execute.
    function testBatchARejectsUnauthorizedAllocator() public {
        manifest.activationId = "batch-a-unauthorized-allocator";
        manifest.vaults[0].allocator = makeAddr("unauthorized-allocator");

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: unauthorized Vault allocator");
    }

    /// @dev Manifest: five affected markets and an empty Vault array, representing markets with no affected Vault.
    /// Executes the Freezer artifact, verifies every market is frozen and unpaused, and confirms no Vault curator
    /// artifact is produced.
    function testBatchAAllowsNoAffectedVault() public {
        manifest.activationId = "batch-a-no-vault";
        delete manifest.vaults;

        _executeBatchA();

        _assertAllFrozenAndUnpaused();
        assertFalse(
            vm.exists(
                _artifactPath(
                    BorrowMarketOffboardingPhase.BATCH_A_CONTAIN,
                    BorrowMarketOffboarding.vaultCuratorFileName(address(vault))
                )
            ),
            "unexpected curator artifact"
        );
    }

    /// @dev Manifest: five affected markets and two real AltoVaults, each with its own curator and allocator; both Vaults
    /// have nonzero caps and one has pending cap/removal work. Executes the independently generated artifacts for each
    /// authorized caller and verifies both Vaults finish with zero caps, no pending work, and no affected market in
    /// either supply queue.
    function testBatchAWritesAndExecutesOneCuratorBatchPerVault() public {
        manifest.activationId = "batch-a-multiple-curators";
        address secondCurator = makeAddr("second-vault-curator");
        address secondAllocator = makeAddr("second-vault-allocator");
        IAltoVault secondVault = _deploySecondVaultWithPendingWork(secondCurator, secondAllocator);

        delete manifest.vaults;
        _pushManifestVault(
            BorrowMarketOffboardingVault({
                allocator: VAULT_ALLOCATOR,
                maxVaultLossAssets: 0,
                reallocationBufferAssets: 1 ether,
                replacementMarkets: new address[](0),
                vault: address(vault)
            })
        );
        _pushManifestVault(
            BorrowMarketOffboardingVault({
                allocator: secondAllocator,
                maxVaultLossAssets: 0,
                reallocationBufferAssets: 1 ether,
                replacementMarkets: new address[](0),
                vault: address(secondVault)
            })
        );

        _executeBatchA();

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertVaultPendingWorkCleared(vault, borrowMarkets[i]);
            _assertVaultPendingWorkCleared(secondVault, borrowMarkets[i]);
        }
        assertEq(vault.supplyQueueLength(), 0, "production Vault supply queue not cleared");
        assertEq(secondVault.supplyQueueLength(), 0, "second Vault supply queue not cleared");
    }

    /// @dev Uses two enabled real destination markets. The first has limited room and must fill to its cap minus the 1 DUSD execution buffer; the second
    /// receives the exact remainder through the terminal max allocation in the generated ordered plan.
    function testBatchAUsesReplacementMarketsInManifestOrder() public {
        manifest.activationId = "batch-a-ordered-replacements";
        uint256 affectedAssets = _affectedVaultSupplyAssets();
        assertGt(affectedAssets, 2 ether, "test requires enough affected supply");

        uint256 firstCap = affectedAssets / 3;
        address firstReplacement = _deployAndEnableReplacementBorrowMarket(firstCap);
        address secondReplacement = _deployAndEnableReplacementBorrowMarket(affectedAssets + 10 ether);
        manifest.vaults[0].replacementMarkets.push(firstReplacement);
        manifest.vaults[0].replacementMarkets.push(secondReplacement);
        _provideAffectedMarketExitLiquidity();

        _executeConfiguredBatchA();

        assertApproxEqAbs(
            firstReplacement.expectedSupplyAssets(address(vault)),
            firstCap - 1 ether,
            2,
            "first replacement target is wrong"
        );
        assertGt(secondReplacement.expectedSupplyAssets(address(vault)), 0, "second replacement received no assets");
        assertEq(_affectedVaultSupplyAssets(), 0, "affected Vault exposure remains");
    }

    /// @dev Gives one replacement less capacity than the first affected market can withdraw. Batch A drains only that
    /// capacity from the first manifest market, reports all remaining exposure, and still completes containment.
    function testBatchAReallocatesOnlyWithinReplacementCapacity() public {
        manifest.activationId = "batch-a-partial-replacement-capacity";
        address replacement = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        uint256 firstWithdrawable = _withdrawableVaultAssets(borrowMarkets[0]);
        assertGt(firstWithdrawable, 2, "first affected market has no partial-withdrawal fixture");
        uint256 replacementCap = firstWithdrawable / 2;
        vm.prank(vault.curator());
        vault.submitCap(replacement, replacementCap);
        manifest.vaults[0].replacementMarkets.push(replacement);

        uint256 affectedBefore = _affectedVaultSupplyAssets();
        uint256[] memory suppliedBefore = new uint256[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            suppliedBefore[i] = borrowMarkets[i].expectedSupplyAssets(address(vault));
        }
        string memory planPath = _batchAAllocatorPlanPath(address(vault));

        _executeConfiguredBatchA();

        uint256 replacementAssets = replacement.expectedSupplyAssets(address(vault));
        uint256 affectedAfter = _affectedVaultSupplyAssets();
        assertApproxEqAbs(replacementAssets, replacementCap - 2 ether, 2, "replacement buffers are wrong");
        assertApproxEqAbs(
            affectedBefore - affectedAfter, replacementAssets, 2, "withdrawal exceeded replacement capacity"
        );
        assertApproxEqAbs(
            affectedAfter, _reportedRemainingAssets(planPath), 2, "reported affected remainder is incorrect"
        );
        assertLt(
            borrowMarkets[0].expectedSupplyAssets(address(vault)),
            suppliedBefore[0],
            "first manifest market was not reduced"
        );
        for (uint256 i = 1; i < borrowMarkets.length; ++i) {
            assertEq(
                borrowMarkets[i].expectedSupplyAssets(address(vault)),
                suppliedBefore[i],
                "later manifest market was reduced"
            );
        }
        _assertAllFrozenAndUnpaused();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertVaultPendingWorkCleared(vault, borrowMarkets[i]);
            if (IMarket(borrowMarkets[i]).position(address(vault)).supplyShares != 0) {
                assertTrue(_isInWithdrawQueue(borrowMarkets[i]), "remaining exposure lost its withdrawal route");
            }
        }
    }

    /// @dev Generates a source-liquidity-limited allocator plan, then lets both the partially liquid affected source and
    /// an already-funded replacement accrue for two hours. The source target and replacement cap buffers keep the
    /// recorded calldata executable while the terminal max allocation supplies exactly what was withdrawn.
    function testBatchAReallocationBuffersInterestUntilExecution() public {
        ReallocationBufferState memory state;
        manifest.activationId = "batch-a-reallocation-interest-buffer";
        state.replacement = _deployRegisteredReplacementBorrowMarket();
        state.replacementPrice = IOracle(IMarket(state.replacement).oracle()).getPrice();
        _enableReplacementForVault(vault, state.replacement, type(uint128).max);
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = state.replacement;
        vm.prank(manifest.vaults[0].allocator);
        vault.setSupplyQueue(supplyQueue);
        vm.mockCall(
            IMarket(state.replacement).oracle(),
            abi.encodeCall(IOracle.getPrice, ()),
            abi.encode(state.replacementPrice)
        );
        manifest.vaults[0].replacementMarkets.push(state.replacement);

        {
            address depositor = makeAddr("buffer-replacement-depositor");
            IERC20 asset = IERC20(vaultToken.asset());
            deal(address(asset), depositor, 10 ether);
            vm.startPrank(depositor);
            asset.approve(address(vaultToken), 10 ether);
            vaultToken.deposit(10 ether, depositor);
            vm.stopPrank();
        }
        _openBorrowPosition(IMarket(state.replacement), makeAddr("buffer-replacement-borrower"), 1 ether, 5 ether);

        state.replacementBefore = state.replacement.expectedSupplyAssets(address(vault));
        state.sourceBefore = borrowMarkets[0].expectedSupplyAssets(address(vault));
        state.sourceWithdrawable = _withdrawableVaultAssets(borrowMarkets[0]);
        state.sourceTokenLiquidity = IERC20(IMarket(borrowMarkets[0]).borrowToken()).balanceOf(borrowMarkets[0]);
        assertGt(state.sourceWithdrawable, 4 ether, "first affected market has no buffered-withdrawal fixture");
        assertLt(state.sourceWithdrawable, state.sourceBefore, "affected source is not partially liquid");

        // Give the replacement enough capacity for all currently available source liquidity.
        // The 1 DUSD source and destination buffers protect against interest accrued before execution.
        state.replacementCap = state.replacementBefore + state.sourceWithdrawable + 1 ether;
        vm.prank(vault.curator());
        vault.submitCap(state.replacement, state.replacementCap);

        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_A_CONTAIN;
        input = scriptHarness.runPhase(phase, manifest, input);
        if (vm.exists(_artifactPath(phase, FREEZE_FILE))) {
            _executeSafeBatch(phase, FREEZE_FILE, manifest.freezerSafe);
        }
        string memory curatorFile = BorrowMarketOffboarding.vaultCuratorFileName(address(vault));
        if (vm.exists(_artifactPath(phase, curatorFile))) {
            _executeSafeBatch(phase, curatorFile, vault.curator());
        }

        string memory allocatorFile = BorrowMarketOffboarding.vaultAllocatorFileName(phase, address(vault));
        string memory plan = vm.readFile(_artifactPath(phase, allocatorFile));
        state.sourceTarget = vm.parseUint(vm.parseJsonString(plan, ".postconditions.expectedAllocations[0].assets"));
        assertEq(
            state.sourceTarget,
            state.sourceBefore - (state.sourceWithdrawable - 1 ether),
            "source target omitted a buffer"
        );

        vm.warp(block.timestamp + 2 hours);
        vm.roll(block.number + 10);
        uint256 sourceBeforeExecution = borrowMarkets[0].expectedSupplyAssets(address(vault));
        uint256 replacementBeforeExecution = state.replacement.expectedSupplyAssets(address(vault));
        assertGt(sourceBeforeExecution, state.sourceBefore, "affected source did not accrue interest");
        assertGt(replacementBeforeExecution, state.replacementBefore, "replacement did not accrue interest");
        assertLt(
            sourceBeforeExecution - state.sourceBefore + replacementBeforeExecution - state.replacementBefore,
            1 ether,
            "two-hour interest exceeds the execution buffer"
        );
        assertEq(
            IERC20(IMarket(borrowMarkets[0]).borrowToken()).balanceOf(borrowMarkets[0]),
            state.sourceTokenLiquidity,
            "source token liquidity changed before execution"
        );
        _executeAllocatorPlan(phase, allocatorFile, manifest.vaults[0].allocator, address(vault));

        uint256 replacementAfter = state.replacement.expectedSupplyAssets(address(vault));
        assertApproxEqAbs(
            borrowMarkets[0].expectedSupplyAssets(address(vault)),
            state.sourceTarget,
            2,
            "buffered source target not reached"
        );
        assertGt(replacementAfter, state.replacementBefore, "replacement received no withdrawn assets");
        assertLe(replacementAfter, state.replacementCap - 1 ether, "replacement consumed its cap buffer");
    }

    /// @dev Mixes unusable replacement entries with one valid final destination. Phase 0 skips the invalid entries,
    /// executes containment, and sends withdrawn assets only to the valid replacement.
    function testBatchASkipsInvalidReplacementMarkets() public {
        manifest.activationId = "batch-a-invalid-replacements";
        address disabled = _deployRegisteredReplacementBorrowMarket();
        address zeroCap = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        vm.prank(vault.curator());
        vault.submitCap(zeroCap, 0);
        address frozen = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        vm.prank(manifest.freezerSafe);
        IPausable(frozen).pause(FROZEN_TYPE, true);
        address paused = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        vm.prank(manifest.freezerSafe);
        IPausable(paused).pause(PAUSE_TYPE, true);
        address valid = _deployAndEnableReplacementBorrowMarket(type(uint128).max);

        address[] storage replacements = manifest.vaults[0].replacementMarkets;
        replacements.push(address(0));
        replacements.push(borrowMarkets[0]);
        replacements.push(makeAddr("unregistered-replacement"));
        replacements.push(disabled);
        replacements.push(zeroCap);
        replacements.push(frozen);
        replacements.push(paused);
        replacements.push(valid);
        replacements.push(valid);
        _provideAffectedMarketExitLiquidity();

        _executeConfiguredBatchA();

        assertEq(_affectedVaultSupplyAssets(), 0, "valid replacement did not receive all available assets");
        assertGt(valid.expectedSupplyAssets(address(vault)), 0, "valid replacement received no assets");
        assertEq(disabled.expectedSupplyAssets(address(vault)), 0, "disabled replacement received assets");
        assertEq(zeroCap.expectedSupplyAssets(address(vault)), 0, "zero-cap replacement received assets");
        assertEq(frozen.expectedSupplyAssets(address(vault)), 0, "frozen replacement received assets");
        assertEq(paused.expectedSupplyAssets(address(vault)), 0, "paused replacement received assets");
    }

    /// @dev Leaves replacementMarkets empty despite affected Vault exposure. Batch A still writes and executes the
    /// freeze, curator, and supply-queue calls while reporting all exposure as remaining in the withdraw queue.
    function testBatchAAllowsEmptyReplacementsWithAffectedExposure() public {
        manifest.activationId = "batch-a-empty-replacements-with-exposure";
        uint256 affectedBefore = _affectedVaultSupplyAssets();
        string memory planPath = _batchAAllocatorPlanPath(address(vault));

        _executeConfiguredBatchA();

        assertEq(_affectedVaultSupplyAssets(), affectedBefore, "empty replacement list changed affected exposure");
        assertEq(_reportedRemainingAssets(planPath), affectedBefore, "remaining exposure was not reported");
        string memory plan = vm.readFile(planPath);
        assertTrue(_jsonTransactionExists(plan, 0), "missing setSupplyQueue transaction");
        assertFalse(_jsonTransactionExists(plan, 1), "unexpected reallocate transaction");
        _assertAllFrozenAndUnpaused();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertVaultPendingWorkCleared(vault, borrowMarkets[i]);
            assertFalse(_isInSupplyQueue(borrowMarkets[i]), "affected market remains in supply queue");
            assertTrue(_isInWithdrawQueue(borrowMarkets[i]), "affected market left withdraw queue");
        }
    }

    /// @dev Uses a real empty AltoVault whose supply queue contains the affected markets. With no affected supply shares,
    /// an empty replacement list is valid and the generated allocator plan contains only setSupplyQueue.
    function testBatchAAllowsEmptyReplacementsWhenNothingIsWithdrawable() public {
        manifest.activationId = "batch-a-supply-queue-only";
        address curator = makeAddr("empty-vault-curator");
        address allocator = makeAddr("empty-vault-allocator");
        IAltoVault emptyVault = _deploySecondVaultWithPendingWork(curator, allocator);

        delete manifest.vaults;
        _pushManifestVault(
            BorrowMarketOffboardingVault({
                allocator: allocator,
                maxVaultLossAssets: 0,
                reallocationBufferAssets: 1 ether,
                replacementMarkets: new address[](0),
                vault: address(emptyVault)
            })
        );

        string memory planPath = _artifactPath(
            BorrowMarketOffboardingPhase.BATCH_A_CONTAIN,
            BorrowMarketOffboarding.vaultAllocatorFileName(
                BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, address(emptyVault)
            )
        );
        _executeConfiguredBatchA();

        assertEq(emptyVault.supplyQueueLength(), 0, "empty Vault supply queue not cleared");
        string memory plan = vm.readFile(planPath);
        assertTrue(_jsonTransactionExists(plan, 0), "missing setSupplyQueue transaction");
        assertFalse(_jsonTransactionExists(plan, 1), "unexpected reallocate transaction");
    }

    /// @dev Moves the Vault into a fresh replacement during containment, then off-boards that replacement while the
    /// Vault is its only supplier and it carries no debt. Nothing accrues on a debt-free market, so Batch A withdraws
    /// the complete position (target `0`) without an interest buffer and a rerun has nothing left to plan.
    function testBatchAExitsDebtFreeSoleSupplierMarketCompletely() public {
        manifest.activationId = "batch-a-debt-free-sole-supplier";
        _executeBatchA();
        address soleSupplied = manifest.vaults[0].replacementMarkets[0];
        uint256 supplied = soleSupplied.expectedSupplyAssets(address(vault));
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = soleSupplied.expectedMarketBalances();
        assertGt(supplied, 0, "Vault did not fund the replacement");
        assertApproxEqAbs(totalSupplyAssets, supplied, 1, "Vault is not the only supplier");
        assertEq(totalBorrowAssets, 0, "replacement market has debt");

        address destination = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        // Cap acceptance warped past the fresh market's oracle heartbeat. Batch A never reads the price, so pin it.
        vm.mockCall(
            IMarket(soleSupplied).oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(initialOraclePrices[0])
        );
        BorrowMarketOffboardingMarket memory offboarded = manifest.markets[0];
        offboarded.market = soleSupplied;
        delete manifest.markets;
        _pushManifestMarket(offboarded);
        _bindManifestState();
        delete manifest.vaults[0].replacementMarkets;
        manifest.vaults[0].replacementMarkets.push(destination);
        manifest.activationId = "batch-a-debt-free-sole-supplier-exit";
        string memory planPath = _batchAAllocatorPlanPath(address(vault));

        _executeConfiguredBatchA();

        assertEq(IMarket(soleSupplied).position(address(vault)).supplyShares, 0, "Vault market supply remains");
        assertEq(_reportedRemainingAssets(planPath), 0, "complete exit reported remaining exposure");
        assertApproxEqAbs(
            destination.expectedSupplyAssets(address(vault)), supplied, 2, "destination did not receive the position"
        );
        string memory plan = vm.readFile(planPath);
        assertEq(
            vm.parseUint(vm.parseJsonString(plan, ".postconditions.expectedAllocations[0].assets")),
            0,
            "debt-free source target is not a complete exit"
        );

        // The source block advanced, so seed a stale plan at the rerun path and verify the rerun removes it.
        string memory rerunPlanPath = _writeStaleBatchAAllocatorPlan(address(vault));
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, manifest, input);
        assertFalse(vm.exists(rerunPlanPath), "rerun planned a withdrawal from an exited market");
    }

    function _batchAAllocatorPlanPath(address affectedVault) private view returns (string memory) {
        return _artifactPath(
            BorrowMarketOffboardingPhase.BATCH_A_CONTAIN,
            BorrowMarketOffboarding.vaultAllocatorFileName(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, affectedVault)
        );
    }

    function _writeStaleBatchAAllocatorPlan(address affectedVault) private returns (string memory path) {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_A_CONTAIN;
        string memory outputDirectory = BorrowMarketOffboarding.artifactDirectory(phase, manifest);
        vm.createDir(outputDirectory, true);
        path = string.concat(outputDirectory, "/", BorrowMarketOffboarding.vaultAllocatorFileName(phase, affectedVault));
        vm.writeFile(path, "{}");
        assertTrue(vm.exists(path), "stale allocator fixture missing");
    }

    function _reportedRemainingAssets(string memory planPath) private view returns (uint256) {
        return
            vm.parseUint(vm.parseJsonString(vm.readFile(planPath), ".postconditions.expectedRemainingAffectedAssets"));
    }

    function _withdrawableVaultAssets(address market) private view returns (uint256) {
        uint256 supplied = market.expectedSupplyAssets(address(vault));
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = market.expectedMarketBalances();
        uint256 liquidity = totalSupplyAssets > totalBorrowAssets ? totalSupplyAssets - totalBorrowAssets : 0;
        uint256 tokenBalance = IERC20(IMarket(market).borrowToken()).balanceOf(market);
        if (tokenBalance < liquidity) liquidity = tokenBalance;
        return supplied < liquidity ? supplied : liquidity;
    }

    function _deploySecondVaultWithPendingWork(address secondCurator, address secondAllocator)
        private
        returns (IAltoVault secondVault)
    {
        secondVault = IAltoVault(
            address(
                new AltoVault({
                    owner: address(this),
                    initialTimelock: 1 days,
                    _asset: vaultToken.asset(),
                    __name: "Batch A DUSD Vault",
                    __symbol: "baDUSD",
                    _marketRegistry: address(marketRegistry)
                })
            )
        );
        secondVault.setCurator(secondCurator);
        secondVault.setIsAllocator(secondAllocator, true);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            vm.prank(secondCurator);
            secondVault.submitCap(borrowMarkets[i], i + 1);
        }
        vm.warp(secondVault.pendingCap(borrowMarkets[0]).validAt);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            secondVault.acceptCap(borrowMarkets[i]);
        }

        address[] memory secondSupplyQueue = new address[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            secondSupplyQueue[i] = borrowMarkets[i];
        }
        vm.prank(secondAllocator);
        secondVault.setSupplyQueue(secondSupplyQueue);

        vm.prank(secondCurator);
        secondVault.submitCap(borrowMarkets[1], 4);
        vm.prank(secondCurator);
        secondVault.submitCap(borrowMarkets[2], 0);
        vm.prank(secondCurator);
        secondVault.submitMarketRemoval(borrowMarkets[2]);
    }

    function _assertVaultContainmentBeforeReallocation(address market) private view {
        _assertVaultPendingWorkCleared(vault, market);
        assertFalse(_isInSupplyQueue(market), "market remains in Vault supply queue");
        if (IMarket(market).position(address(vault)).supplyShares != 0) {
            assertTrue(_isInWithdrawQueue(market), "supplied market absent from withdraw queue");
        }
    }

    function _assertVaultPendingWorkCleared(IAltoVault affectedVault, address market) private view {
        MarketConfig memory marketConfig = affectedVault.config(market);
        PendingUint192 memory pendingCap = affectedVault.pendingCap(market);
        assertEq(marketConfig.cap, 0, "Vault cap not zero");
        assertEq(marketConfig.removableAt, 0, "Vault pending removal remains");
        assertEq(pendingCap.validAt, 0, "Vault pending cap remains");
    }

    function _assertEntrancesBlocked(IMarket market, address caller) private {
        _assertFrozenRevert(
            address(market), caller, abi.encodeCall(IMarketBase.addSupply, (1, 0, caller)), "addSupply succeeded"
        );
        _assertFrozenRevert(
            address(market), caller, abi.encodeCall(IMarketBase.addCollateral, (1, caller)), "addCollateral succeeded"
        );
        _assertFrozenRevert(
            address(market),
            caller,
            abi.encodeCall(IMarketBase.borrow, (1, 0, caller, caller, bytes(""))),
            "borrow succeeded"
        );
    }

    function _assertFrozenRevert(address target, address caller, bytes memory data, string memory message) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        assertFalse(success, message);
        assertEq(returnData, abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE), "wrong freeze revert");
    }

    function _provideAffectedMarketExitLiquidity() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            if (address(market).expectedSupplyAssets(address(vault)) == 0) continue;

            // Live debt prevents a full Vault exit. A real outside supply buffer isolates the reallocation path while
            // preserving the market's totalSupply >= totalBorrowed accounting invariant.
            uint256 suppliedAssets = market.totalBorrowed().assets + 1 ether;
            address supplier = makeAddr(string.concat("reallocation-liquidity-", vm.toString(i)));
            IERC20 asset = IERC20(market.borrowToken());
            deal(address(asset), supplier, suppliedAssets);

            bool wasFrozen = market.paused(FROZEN_TYPE);
            if (wasFrozen) {
                vm.prank(manifest.freezerSafe);
                IPausable(address(market)).pause(FROZEN_TYPE, false);
            }
            vm.startPrank(supplier);
            asset.approve(address(market), suppliedAssets);
            market.addSupply(suppliedAssets, 0, supplier);
            vm.stopPrank();
            if (wasFrozen) {
                vm.prank(manifest.freezerSafe);
                IPausable(address(market)).pause(FROZEN_TYPE, true);
            }
        }
    }

    function _depositAndAssertReplacementOnly(address replacement) private {
        uint256[] memory affectedSharesBefore = new uint256[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            affectedSharesBefore[i] = IMarket(borrowMarkets[i]).position(address(vault)).supplyShares;
        }
        uint256 replacementSharesBefore = IMarket(replacement).position(address(vault)).supplyShares;
        address depositor = makeAddr("post-containment-depositor");
        IERC20 asset = IERC20(vaultToken.asset());
        deal(address(asset), depositor, 1 ether);

        vm.startPrank(depositor);
        asset.approve(address(vaultToken), 1 ether);
        vaultToken.deposit(1 ether, depositor);
        vm.stopPrank();

        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertEq(
                IMarket(borrowMarkets[i]).position(address(vault)).supplyShares,
                affectedSharesBefore[i],
                "deposit allocated to affected market"
            );
        }
        assertGt(
            IMarket(replacement).position(address(vault)).supplyShares,
            replacementSharesBefore,
            "deposit not allocated to replacement"
        );
    }
}
