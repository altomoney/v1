// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingPhase, BorrowMarketOffboardingVault} from "../IBorrowMarketOffboarding.sol";

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

        // A rerun retains a source-position plan while illiquid affected shares remain. Executing it is idempotent.
        uint256 remainingAssets = _affectedVaultSupplyAssets();
        string memory allocatorFile = BorrowMarketOffboarding.vaultAllocatorFileName(
            BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, address(vault)
        );
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, manifest, input);
        assertTrue(
            vm.exists(_artifactPath(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, allocatorFile)),
            "outstanding exposure plan missing"
        );
        _executeAllocatorPlan(
            BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, allocatorFile, manifest.vaults[0].allocator, address(vault)
        );
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
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, manifest, input);
        assertFalse(
            vm.exists(
                _artifactPath(
                    BorrowMarketOffboardingPhase.BATCH_A_CONTAIN,
                    BorrowMarketOffboarding.vaultAllocatorFileName(
                        BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, address(vault)
                    )
                )
            ),
            "stale Batch A allocator plan remains"
        );

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
                replacementMarkets: new address[](0),
                vault: address(vault)
            })
        );
        _pushManifestVault(
            BorrowMarketOffboardingVault({
                allocator: secondAllocator,
                maxVaultLossAssets: 0,
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

    /// @dev Uses two enabled real destination markets. The first has limited room and must fill to its cap; the second
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
            firstReplacement.expectedSupplyAssets(address(vault)), firstCap, 2, "first replacement did not fill"
        );
        assertGt(secondReplacement.expectedSupplyAssets(address(vault)), 0, "second replacement received no assets");
        assertEq(_affectedVaultSupplyAssets(), 0, "affected Vault exposure remains");
    }

    /// @dev Leaves replacementMarkets empty while the production Vault has withdrawable affected exposure. Generation
    /// must stop because an allocator plan may never withdraw assets without enough destination cap room.
    function testBatchARejectsInsufficientReplacementCapacity() public {
        manifest.activationId = "batch-a-insufficient-replacement-capacity";
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: insufficient replacement capacity");
    }

    /// @dev Supplies invalid replacement lists to the production Vault and verifies the manifest rejects zero, duplicate,
    /// affected, unregistered, disabled, zero-cap, frozen, and paused destination markets.
    function testBatchARejectsInvalidReplacementMarkets() public {
        manifest.activationId = "batch-a-invalid-replacements";

        _setOnlyReplacement(address(0));
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: zero replacement market");

        _setOnlyReplacement(borrowMarkets[0]);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: affected market is replacement");

        _setOnlyReplacement(makeAddr("unregistered-replacement"));
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: replacement market not registered");

        address disabled = _deployRegisteredReplacementBorrowMarket();
        _setOnlyReplacement(disabled);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: replacement market not enabled");

        address duplicate = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        _setOnlyReplacement(duplicate);
        manifest.vaults[0].replacementMarkets.push(duplicate);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: duplicate replacement market");

        vm.prank(vault.curator());
        vault.submitCap(duplicate, 0);
        _setOnlyReplacement(duplicate);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: replacement market has zero cap");

        address frozen = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        vm.prank(manifest.freezerSafe);
        IPausable(frozen).pause(FROZEN_TYPE, true);
        _setOnlyReplacement(frozen);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: replacement market frozen");

        address paused = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        vm.prank(manifest.freezerSafe);
        IPausable(paused).pause(PAUSE_TYPE, true);
        _setOnlyReplacement(paused);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, "Batch A: replacement market paused");
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

    function _setOnlyReplacement(address replacement) private {
        delete manifest.vaults[0].replacementMarkets;
        manifest.vaults[0].replacementMarkets.push(replacement);
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
