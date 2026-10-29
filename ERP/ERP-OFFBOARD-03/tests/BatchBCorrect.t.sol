// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultOffboardingTestBase} from "./VaultOffboardingTestBase.sol";
import {
    VaultOffboardingAction as Action,
    VaultOffboardingPhase as Phase,
    VaultOffboardingSeverity as Severity,
    VaultOffboardingRemovalTarget,
    VaultOffboardingRecoveryTarget
} from "../IVaultOffboarding.sol";
import {IAltoVaultErrors} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {ConstantsLib} from "@alto/lending/libraries/ConstantsLib.sol";
import {ERPVaultQueue} from "../../libraries/ERPVaultQueue.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Spec: ERP-OFFBOARD-03, sections 4 (Batch B severities/common rules) and 5 (acceptance criteria).
/// All response calls come from production-script artifacts. External market shocks are fixture actions only;
/// these tests do not certify incident-specific governance evidence or economic limits.
contract BatchBCorrectTest is VaultOffboardingTestBase {
    using AltoBalancesLib for address;

    function setUp() public {
        _setUpFork();
    }

    function _activationId() internal pure override returns (string memory) {
        return "test-vault-batch-b";
    }

    // Ordinary queue updates preserve positions; only the withdrawal order or empty configurations may change.

    /// @dev Uses the pinned live Vault after Batch A, a valid notice and a reversed current queue.
    /// Executes the generated allocator file; queue order changes while positions, administration and closed caps remain.
    function testBatchBPinnedLiveVaultReorderExecutesGeneratedAllocatorFile() public {
        manifest.step = uint32(msg.sig);
        _completeBatchA();
        phase = Phase.BATCH_B_CORRECT;
        manifest.t0 = block.timestamp;
        manifest.noticeAt = manifest.t0 - 7 days;
        manifest.allocator = manifest.curatorSafe;
        address[] memory current = ERPVaultQueue.withdrawQueue(vault);
        for (uint256 i; i < current.length; ++i) {
            manifest.withdrawQueue.push(current[current.length - i - 1]);
        }
        uint256[] memory positions = _positionShares();
        bytes32 controls = _controlsHash();
        _generate();
        _executeAllocator();
        assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.withdrawQueue);
        assertEq(_positionShares(), positions);
        assertEq(_controlsHash(), controls);
        _assertClosedAllocation();
    }

    /// @dev Uses two funded markets, two shareholders and an approved reversed withdrawal order.
    /// Executes the queue update and an exit; the first approved market funds it without changing another user's claim.
    function testBatchBReordersCurrentIndexesAndChangesWhichMarketFundsExits() public {
        _startBatchB();
        address bob = makeAddr("remaining shareholder");
        vm.prank(alice);
        shares.transfer(bob, 200 ether);
        manifest.shareholders.push(bob);
        _reverseFundedQueue();
        uint256 totalBefore = shares.totalSupply();
        uint256 assetsBefore = shares.totalAssets();
        bytes32 controls = _controlsHash();
        _generate();
        _executeAllocator();
        assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.withdrawQueue);
        assertEq(shares.totalAssets(), assetsBefore);
        assertEq(shares.totalSupply(), totalBefore);
        vm.prank(alice);
        shares.withdraw(150 ether, alice, alice);
        assertEq(manifest.markets[0].expectedSupplyAssets(manifest.vault), 600 ether);
        assertEq(manifest.markets[1].expectedSupplyAssets(manifest.vault), 250 ether);
        assertEq(shares.balanceOf(bob), 200 ether);
        assertEq(shares.maxWithdraw(bob), 200 ether);
        assertEq(asset.balanceOf(alice), 150 ether);
        assertEq(_controlsHash(), controls);
        _assertClosedAllocation();
    }

    /// @dev Uses an ordinary queue manifest omitting only the empty fixture market.
    /// Executes the generated update; its configuration is deleted while funded markets and shareholder supply remain.
    function testBatchBOrdinaryRemovalDeletesOnlyZeroShareConfiguration() public {
        _startBatchB();
        manifest.withdrawQueue = _firstTwo();
        uint256 sharesBefore = shares.totalSupply();
        _generate();
        _executeAllocator();
        assertFalse(vault.config(manifest.markets[2]).enabled);
        assertEq(vault.withdrawQueueLength(), 2);
        assertEq(shares.totalSupply(), sharesBefore);
        assertTrue(vault.config(manifest.markets[0]).enabled);
        assertTrue(vault.config(manifest.markets[1]).enabled);
    }

    /// @dev Uses ordinary queue updates omitting a funded market with matured removal permission, then a zero-asset dust position.
    /// Rejects both omissions; a native removal timestamp or rounded asset estimate cannot authorize dropping supply shares.
    function testBatchBOrdinaryQueueRejectsMaturedFundedRemovalAndZeroAssetShareDust() public {
        _startBatchB();
        _readyRemoval(_oneAddress(manifest.markets[0]));
        manifest.action = Action.UPDATE_WITHDRAW_QUEUE;
        _expectPreparationRevert("Batch B: ordinary funded market omitted");
        // Retain the approved funded market, but omit a different position whose assets round to zero.
        address market = manifest.markets[2];
        deal(address(asset), address(this), 1);
        asset.approve(market, 1);
        IMarket(market).addSupply(0, 1, manifest.vault);
        assertEq(market.expectedSupplyAssets(manifest.vault), 0);
        manifest.withdrawQueue = _firstTwo();
        _expectPreparationRevert("Batch B: ordinary funded market omitted");
    }

    /// @dev Varies an ordinary queue manifest with an unknown addition, a duplicate, or an unauthorized/zero allocator.
    /// Rejects each invalid preparation without changing queue state or retaining executable output.
    function testBatchBRejectsQueueAdditionsDuplicatesAndUnauthorizedAllocator() public {
        _startBatchB();
        manifest.withdrawQueue.push(makeAddr("not in current queue"));
        _expectPreparationRevert("Batch B: queue cannot add markets");
        manifest.withdrawQueue.pop();
        manifest.withdrawQueue[2] = manifest.withdrawQueue[0];
        _expectPreparationRevert("ERP manifest: duplicate address");
        _reverseFundedQueue();
        manifest.allocator = revokedAllocator;
        _expectPreparationRevert("Batch B: unauthorized allocator");
        manifest.allocator = address(0);
        _expectPreparationRevert("Batch B: unauthorized allocator");
    }

    /// @dev Replaces a prepared reorder with the unchanged current queue and no allocator address.
    /// Regeneration produces no transaction and removes the previous queue plan without requiring execution authority.
    function testBatchBQueueNoOpNeedsNoAllocatorAuthorityAndClearsStalePlan() public {
        _startBatchB();
        _reverseFundedQueue();
        _generate();
        assertTrue(vm.exists(_path("vault-allocator.json")));
        manifest.withdrawQueue = ERPVaultQueue.withdrawQueue(vault);
        manifest.allocator = address(0);
        _generate();
        _assertNoCalldata();
    }

    /// @dev Uses a reordered queue that retains a funded market with an existing pending removal.
    /// Executes the reorder; the market stays queued and its original removal timestamp is preserved.
    function testBatchBRetainedPendingRemovalDoesNotBlockQueueReorder() public {
        _startBatchB();
        vm.prank(manifest.curatorSafe);
        vault.submitMarketRemoval(manifest.markets[0]);
        uint256 readyAt = vault.config(manifest.markets[0]).removableAt;
        _reverseFundedQueue();
        _executeCorrection();
        assertEq(vault.config(manifest.markets[0]).removableAt, readyAt);
        assertEq(vault.withdrawQueue(1), manifest.markets[0]);
    }

    /// @dev Uses valid queue orders with the curator and then the Timelock as allocator.
    /// Executes both generated routes; each approved order takes effect after the applicable native authorization/delay.
    function testBatchBQueueRoutesThroughCuratorOrRealGovernanceTimelock() public {
        _startBatchB();
        manifest.allocator = manifest.curatorSafe;
        _reverseFundedQueue();
        _executeCorrection();
        manifest.withdrawQueue = manifest.markets;
        manifest.allocator = address(timelock);
        _generate();
        assertFalse(vm.exists(_path("vault-allocator.json")));
        _executeOwner();
        assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.markets);
    }

    /// @dev Prepares an ordinary omission while a market is empty, then supplies assets to it before execution.
    /// Executes the generated file expecting native rejection; the new position and queue remain intact.
    function testBatchBGeneratedEmptyRemovalRevertsIfMarketBecomesFunded() public {
        _startBatchB();
        manifest.withdrawQueue = _firstTwo();
        _generate();
        _supplyOnBehalf(manifest.markets[2], 1 ether, manifest.vault);
        bytes32 beforeState = _claimsHash();
        (address target, bytes memory data) = _allocatorTransaction();
        vm.prank(manifest.allocator);
        (bool ok,) = target.call(data);
        assertFalse(ok, "new funded position was discarded");
        assertEq(_claimsHash(), beforeState);
    }

    // Severity sets notice and reporting dates, not a transaction schedule or a deadline for claims.

    /// @dev Varies Medium, High and Critical notices across missing/future dates, exact boundaries and waiver references.
    /// Rejects invalid notices; valid boundaries and permitted High/Critical waivers execute the approved queue changes.
    function testBatchBSeverityNoticeBoundariesAndWaivers() public {
        _startBatchB();
        for (uint256 severity; severity < 3; ++severity) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += severity;
            manifest.severity = Severity(severity);
            bool medium = severity == 0;
            manifest.noticeAt = 0;
            _expectPreparationRevert(medium ? "Batch B: Medium notice missing" : "Batch B: notice missing");
            manifest.noticeAt = manifest.t0 + 1;
            _expectPreparationRevert(medium ? "Batch B: Medium notice missing" : "Batch B: notice missing");
            uint256 duration = medium ? 7 days : severity == 1 ? 1 days : 0;
            if (duration != 0) {
                manifest.noticeAt = manifest.t0 - duration + 1;
                _expectPreparationRevert(medium ? "Batch B: Medium notice missing" : "Batch B: High notice too short");
            }
            manifest.noticeAt = manifest.t0 - duration;
            _reverseFundedQueue();
            _executeCorrection();
            assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.withdrawQueue);
            manifest.noticeWaived = true;
            manifest.noticeAt = 0;
            _expectPreparationRevert(medium ? "Batch B: Medium notice missing" : "Batch B: waiver reference missing");
            manifest.noticeWaiverReference = "governance-approved disclosure waiver";
            if (medium) {
                _expectPreparationRevert("Batch B: Medium notice missing");
            } else {
                manifest.withdrawQueue = manifest.markets;
                _executeCorrection();
                assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.markets);
            }
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Supplies each of the five Batch B actions with a future T0 or missing Medium notice.
    /// Rejects every action before operation-specific work, preserving Vault state and clearing executable artifacts.
    function testBatchBEveryActionRequiresT0AndNotice() public {
        _startBatchB();
        _selectRemoval(_firstTwo());
        _selectRecovery(_firstTwo());
        for (uint256 i; i < 5; ++i) {
            manifest.action = Action(i);
            manifest.t0 = block.timestamp + 1;
            manifest.noticeAt = manifest.t0 - 7 days;
            _expectPreparationRevert("Batch B: before T0");
            manifest.t0 = block.timestamp;
            manifest.noticeAt = 0;
            _expectPreparationRevert("Batch B: Medium notice missing");
        }
    }

    /// @dev Uses each severity with valid notice, actions between checkpoints and residual claims beyond the active window.
    /// Executes queue updates and later exceptional recovery; elapsed reporting dates never discard outstanding claims.
    function testBatchBActionsBetweenCheckpointsAndResidualClaimsAfterEveryWindow() public {
        _startBatchB();
        bytes32 controls = _controlsHash();
        uint256 supplyBefore = shares.totalSupply();
        for (uint256 severity; severity < 3; ++severity) {
            manifest.severity = Severity(severity);
            manifest.t0 = block.timestamp;
            manifest.noticeAt = manifest.t0 - 7 days;
            vm.warp(manifest.t0 + 12 hours);
            _reverseFundedQueue();
            _executeCorrection();
            assertFalse(vm.parseJsonBool(vm.readFile(_path("exposure-report.json")), ".activeWindowElapsed"));
            uint256 daysElapsed = severity == 0 ? 28 : severity == 1 ? 14 : 7;
            vm.warp(manifest.t0 + daysElapsed * 1 days);
            manifest.withdrawQueue = manifest.markets;
            _executeCorrection();
            assertTrue(vm.parseJsonBool(vm.readFile(_path("exposure-report.json")), ".activeWindowElapsed"));
            manifest.withdrawQueue = _oneAddress(manifest.markets[2]);
            _expectPreparationRevert("Batch B: ordinary funded market omitted");
        }
        assertEq(shares.totalSupply(), supplyBefore);
        assertEq(_controlsHash(), controls);
        vm.warp(block.timestamp + 365 days);
        _readyRemoval(_oneAddress(manifest.markets[0]));
        _executeCorrection();
        manifest.quarantinedMarkets = _oneAddress(manifest.markets[0]);
        _submitRecovery(_oneAddress(manifest.markets[0]));
        _matureRecovery();
        _executeCorrection();
        _assertClosedAllocation();
        assertEq(_controlsHash(), controls);
    }

    /// @dev Varies all five actions with a remaining supply queue, nonzero fee, accepted cap or pending cap increase.
    /// Rejects each containment violation before action preparation and leaves the existing state unchanged.
    function testBatchBCommonContainmentGuardsApplyToEveryAction() public {
        _startBatchB();
        _selectRemoval(_firstTwo());
        _selectRecovery(_firstTwo());
        // Cases: nonempty supply queue, nonzero fee, accepted cap, pending cap.
        for (uint256 state; state < 4; ++state) {
            uint256 snapshot = vm.snapshotState();
            if (state == 0 || state == 2 || state == 3) {
                vm.prank(manifest.curatorSafe);
                vault.submitCap(manifest.markets[2], 1 ether);
                if (state != 3) {
                    vm.warp(vault.pendingCap(manifest.markets[2]).validAt);
                    vault.acceptCap(manifest.markets[2]);
                }
                if (state == 0) {
                    vm.prank(manifest.curatorSafe);
                    vault.setSupplyQueue(_oneAddress(manifest.markets[2]));
                }
            } else {
                vm.prank(address(timelock));
                vault.setFee(1);
            }
            for (uint256 action; action < 5; ++action) {
                manifest.action = Action(action);
                _expectPreparationRevert(
                    state == 0
                        ? "Batch B: supply queue remains"
                        : state == 1 ? "Batch B: fee remains" : "Batch B: allocation capacity remains"
                );
            }
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses an approved exceptional market and each severity before its removal or cap-acceptance timestamp.
    /// Rejects early execution preparation; generated removal and recovery succeed only after their native delays.
    function testBatchBNoSeverityBypassesNativeRemovalOrRecoveryDelay() public {
        _startBatchB();
        _selectRemoval(_oneAddress(manifest.markets[0]));
        manifest.action = Action.SUBMIT_REMOVAL;
        _executeCorrection();
        manifest.withdrawQueue = new address[](2);
        manifest.withdrawQueue[0] = manifest.markets[1];
        manifest.withdrawQueue[1] = manifest.markets[2];
        manifest.action = Action.EXECUTE_REMOVAL;
        for (uint256 i; i < 3; ++i) {
            manifest.severity = Severity(i);
            _expectPreparationRevert("Batch B: market removal timelock not elapsed");
        }
        vm.warp(vault.config(manifest.markets[0]).removableAt);
        _executeCorrection();
        manifest.quarantinedMarkets = _oneAddress(manifest.markets[0]);
        _submitRecovery(_oneAddress(manifest.markets[0]));
        manifest.action = Action.ACCEPT_RECOVERY_CAP;
        for (uint256 i; i < 3; ++i) {
            manifest.severity = Severity(i);
            _expectPreparationRevert("Batch B: recovery cap not ready");
        }
        _matureRecovery();
        _executeCorrection();
    }

    // Exceptional removals require exact per-market approvals, native readiness and combined accounting limits.

    /// @dev Uses two removal targets, then a rerun where only one still needs a submission.
    /// Executes generated submissions; the existing timestamp is retained, the missing one starts anew, then reruns no-op.
    function testBatchBMultipleRemovalSubmissionsPreserveExistingPendingTimestamps() public {
        _startBatchB();
        address[] memory targets = _firstTwo();
        (targets[0], targets[1]) = (targets[1], targets[0]);
        _selectRemoval(targets);
        manifest.action = Action.SUBMIT_REMOVAL;
        _generate();
        uint256 submittedAt = block.timestamp;
        _executeCuratorAtomic();
        assertEq(vault.config(targets[0]).removableAt, submittedAt + vault.timelock());
        assertEq(vault.config(targets[1]).removableAt, submittedAt + vault.timelock());
        vm.warp(block.timestamp + 1 hours);
        vm.prank(manifest.curatorSafe);
        vault.revokePendingMarketRemoval(targets[1]);
        _generate();
        _executeCuratorAtomic();
        assertEq(vault.config(targets[0]).removableAt, submittedAt + vault.timelock());
        assertEq(vault.config(targets[1]).removableAt, block.timestamp + vault.timelock());
        _generate();
        _assertNoCalldata();
    }

    /// @dev Uses exact approvals for two funded targets omitted from the approved queue after their native delays.
    /// Executes removal; configurations disappear, supply shares remain, quarantine is exact and native loss accrues later.
    function testBatchBMultipleRemovalExecutionPreservesSharesAndRecordsExactQuarantine() public {
        _startBatchB();
        uint256 supplyBefore = shares.totalSupply();
        bytes32 controls = _controlsHash();
        uint256[] memory positions = _positionShares();
        _readyRemoval(_firstTwo());
        _generate();
        uint256 walletBefore = asset.balanceOf(manifest.vault);
        uint256 liquidityBefore = asset.balanceOf(manifest.markets[0]) + asset.balanceOf(manifest.markets[1]);
        _executeAllocator();
        assertEq(vault.withdrawQueueLength(), 1);
        assertEq(vault.withdrawQueue(0), manifest.markets[2]);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 600 ether);
        assertEq(vault.quarantinedAssets(manifest.markets[1]), 400 ether);
        for (uint256 i; i < 2; ++i) {
            assertFalse(vault.config(manifest.markets[i]).enabled);
            assertEq(vault.config(manifest.markets[i]).removableAt, 0);
            assertEq(IMarket(manifest.markets[i]).position(manifest.vault).supplyShares, positions[i]);
        }
        assertEq(shares.totalSupply(), supplyBefore);
        assertEq(asset.balanceOf(manifest.vault), walletBefore);
        assertEq(asset.balanceOf(manifest.markets[0]) + asset.balanceOf(manifest.markets[1]), liquidityBefore);
        assertEq(shares.maxWithdraw(alice), 0);
        assertEq(vault.lostAssets(), 0, "queue update should not accrue stored loss");
        assertEq(shares.totalAssets(), 1_000 ether, "calculated loss remains recognized");
        vm.prank(alice);
        shares.withdraw(0, alice, alice); // Trigger native accounting without moving assets.
        assertEq(vault.lostAssets(), 1_000 ether);
        assertEq(_controlsHash(), controls);
    }

    /// @dev Uses two targets with staggered readiness, mismatched approvals and a later permissionless supply donation.
    /// Rejects every unready/stale approval; refreshed exact positions allow the complete queue change to execute.
    function testBatchBRemovalRequiresAllTargetsReadyAndFreshApprovals() public {
        _startBatchB();
        _selectRemoval(_firstTwo());
        manifest.action = Action.SUBMIT_REMOVAL;
        _executeCorrection();
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(manifest.curatorSafe);
        vault.revokePendingMarketRemoval(manifest.markets[1]);
        vault.submitMarketRemoval(manifest.markets[1]);
        vm.stopPrank();
        manifest.action = Action.EXECUTE_REMOVAL;
        manifest.withdrawQueue = _oneAddress(manifest.markets[2]);
        vm.warp(vault.config(manifest.markets[0]).removableAt);
        _expectPreparationRevert("Batch B: market removal timelock not elapsed");
        vm.warp(vault.config(manifest.markets[1]).removableAt);
        manifest.removalTargets[0].approvedSupplyShares++;
        _expectPreparationRevert("Batch B: position differs from approval");
        _selectRemoval(_firstTwo());
        manifest.removalTargets[1].approvedExpectedAssets++;
        _expectPreparationRevert("Batch B: position differs from approval");
        _selectRemoval(_firstTwo());
        _supplyOnBehalf(manifest.markets[0], 1, manifest.vault);
        _expectPreparationRevert("Batch B: position differs from approval");
        _selectRemoval(_firstTwo());
        _executeCorrection();
    }

    /// @dev Uses exceptional execution with either a selected target retained or an unselected funded market omitted.
    /// Rejects both invalid approved queues without deleting funded positions or preparing an executable plan.
    function testBatchBRemovalRequiresEveryTargetOmittedAndProtectsOtherFundedMarkets() public {
        _startBatchB();
        _readyRemoval(_oneAddress(manifest.markets[0]));
        manifest.withdrawQueue = manifest.markets;
        _expectPreparationRevert("Batch B: removal target retained");
        manifest.withdrawQueue = _oneAddress(manifest.markets[2]);
        _expectPreparationRevert("Batch B: ordinary funded market omitted");
    }

    /// @dev Varies submission targets between an empty market, a disabled quarantine and an unauthorized curator.
    /// Rejects misuse of exceptional removal while retaining positions and existing permissions.
    function testBatchBRemovalRejectsEmptyDisabledAndUnauthorizedTargets() public {
        _startBatchB();
        _selectRemoval(_oneAddress(manifest.markets[2]));
        manifest.action = Action.SUBMIT_REMOVAL;
        _expectPreparationRevert("Batch B: use ordinary removal for empty market");
        _selectRemoval(_firstTwo());
        address curator = manifest.curatorSafe;
        manifest.curatorSafe = makeAddr("wrong curator");
        _expectPreparationRevert("ERP: unauthorized curator Safe");
        manifest.curatorSafe = curator;
        _quarantine(_oneAddress(manifest.markets[0]));
        manifest.action = Action.SUBMIT_REMOVAL;
        _expectPreparationRevert("Batch B: removal needs enabled market");
    }

    /// @dev Uses ready targets with exact positions but progressively insufficient per-market, aggregate, quarantine or loss limits.
    /// Rejects each insufficient budget; the exact allowed bounds permit execution and record both quarantines.
    function testBatchBRemovalIndividualAndCombinedLimitsFailIndependently() public {
        _startBatchB();
        _readyRemoval(_firstTwo());
        manifest.removalTargets[0].maxExceptionalRemovedAssets = 600 ether - 1;
        _expectPreparationRevert("Batch B: removal limit exceeded");
        manifest.removalTargets[0].maxExceptionalRemovedAssets = 600 ether;
        manifest.maxExceptionalRemovedAssets = 1_000 ether - 1;
        _expectPreparationRevert("Batch B: combined removal limit exceeded");
        manifest.maxExceptionalRemovedAssets = 1_000 ether;
        manifest.maxQuarantinedAssets = 1_000 ether - 1;
        _expectPreparationRevert("Batch B: removal exceeds accounting limits");
        manifest.maxQuarantinedAssets = 1_000 ether;
        manifest.maxLostAssets = 1_000 ether - 1;
        _expectPreparationRevert("Batch B: removal exceeds accounting limits");
        manifest.maxLostAssets = 1_000 ether;
        _executeCorrection();
    }

    /// @dev Starts with one quarantined market and stored loss, then requests removal of another funded market.
    /// Includes existing residue in combined limits; valid limits allow real Timelock execution and exact total quarantine.
    function testBatchBRemovalIncludesExistingQuarantineAndStoredLoss() public {
        _startBatchB();
        _quarantine(_oneAddress(manifest.markets[0]));
        vm.prank(alice);
        shares.withdraw(0, alice, alice);
        assertEq(vault.lostAssets(), 600 ether);
        _readyRemoval(_oneAddress(manifest.markets[1]));
        manifest.maxQuarantinedAssets = 400 ether;
        _expectPreparationRevert("Batch B: removal exceeds accounting limits");
        manifest.maxQuarantinedAssets = 1_000 ether;
        manifest.maxLostAssets = 600 ether;
        _expectPreparationRevert("Batch B: removal exceeds accounting limits");
        manifest.maxLostAssets = 1_000 ether;
        manifest.allocator = address(timelock);
        _generate();
        _executeOwner();
        assertEq(
            vault.quarantinedAssets(manifest.markets[0]) + vault.quarantinedAssets(manifest.markets[1]), 1_000 ether
        );
    }

    // Recovery must return every temporary cap to zero in the same atomic curator Safe transaction.

    /// @dev Uses two quarantined markets with approved caps and a deliberately reversed target order.
    /// Executes one real Safe recovery batch; queue order follows targets, caps close, accounting recovers and exits work.
    function testBatchBMultipleRecoveriesExecuteAtomicAcceptResetPairsInOrder() public {
        _startBatchB();
        _quarantine(_firstTwo());
        bytes32 controls = _controlsHash();
        uint256[] memory positions = _positionShares();
        address[] memory targets = _firstTwo();
        (targets[0], targets[1]) = (targets[1], targets[0]);
        _submitRecovery(targets);
        assertEq(vault.pendingCap(targets[0]).value, 1);
        assertEq(vault.pendingCap(targets[1]).value, 2);
        _expectPreparationRevert("Batch B: allocation capacity remains"); // Re-submission cannot overwrite pending caps.
        _matureRecovery();
        _generate();
        uint256 supplyBefore = shares.totalSupply();
        _executeCuratorAtomic();
        assertEq(vault.withdrawQueue(0), manifest.markets[2]);
        assertEq(vault.withdrawQueue(1), targets[0]);
        assertEq(vault.withdrawQueue(2), targets[1]);
        assertEq(vault.lostAssets(), 0);
        assertEq(vault.lastTotalAssets(), 1_000 ether);
        assertEq(shares.totalSupply(), supplyBefore);
        for (uint256 i; i < 2; ++i) {
            assertEq(vault.quarantinedAssets(manifest.markets[i]), 0);
            assertEq(IMarket(manifest.markets[i]).position(manifest.vault).supplyShares, positions[i]);
        }
        _assertClosedAllocation();
        assertEq(shares.maxWithdraw(alice), 1_000 ether);
        assertEq(_controlsHash(), controls);
        uint256 exitShares = shares.balanceOf(alice) / 2;
        vm.prank(alice);
        shares.redeem(exitShares, alice, alice);
        assertEq(asset.balanceOf(alice), 500 ether);
    }

    /// @dev Uses two disabled quarantine targets with bounded recovery caps, delaying execution after preparation.
    /// Executes the generated Safe file; both pending timestamps start at execution time plus the Vault's native delay.
    function testBatchBRecoverySubmissionStartsNativeDelayAtExecution() public {
        _startBatchB();
        _quarantine(_firstTwo());
        _selectRecovery(_firstTwo());
        manifest.action = Action.SUBMIT_RECOVERY_CAP;
        _generate();
        vm.warp(block.timestamp + 3 days);
        uint256 executedAt = block.timestamp;
        _executeCuratorAtomic();
        assertEq(vault.pendingCap(manifest.markets[0]).validAt, executedAt + vault.timelock());
        assertEq(vault.pendingCap(manifest.markets[1]).validAt, executedAt + vault.timelock());
    }

    /// @dev Uses staggered pending recovery caps and then a manifest value that differs from the second pending cap.
    /// Rejects partial readiness and mismatch; matching mature targets recover together with zero final caps.
    function testBatchBRecoveryWaitsForAllSelectedCapsAndChecksMatchingValues() public {
        _startBatchB();
        _quarantine(_firstTwo());
        _submitRecovery(_firstTwo());
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(manifest.curatorSafe);
        vault.revokePendingCap(manifest.markets[1]);
        vault.submitCap(manifest.markets[1], 2);
        vm.stopPrank();
        manifest.action = Action.ACCEPT_RECOVERY_CAP;
        vm.warp(vault.pendingCap(manifest.markets[0]).validAt);
        _expectPreparationRevert("Batch B: recovery cap not ready");
        vm.warp(vault.pendingCap(manifest.markets[1]).validAt);
        manifest.recoveryTargets[1].recoveryCap = 1;
        _expectPreparationRevert("Batch B: recovery cap not ready");
        manifest.recoveryTargets[1].recoveryCap = 2;
        _executeCorrection();
    }

    /// @dev Uses one permissionlessly accepted cap, either still positive or previously reset, alongside a pending target.
    /// Executes recovery; both targets finish with zero caps/quarantine, reruns no-op and completed targets still count in limits.
    function testBatchBRecoveryExecutesAcceptedCapResetAndSkipsCompletedTargets() public {
        _startBatchB();
        _quarantine(_firstTwo());
        _submitRecovery(_firstTwo());
        _matureRecovery();
        vault.acceptCap(manifest.markets[0]); // Permissionless acceptance precedes the response.
        for (uint256 completed; completed < 2; ++completed) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += completed;
            if (completed != 0) {
                vm.prank(manifest.curatorSafe);
                vault.submitCap(manifest.markets[0], 0); // Previously completed target fixture.
            } else {
                assertGt(vault.config(manifest.markets[0]).cap, 0);
                assertEq(shares.maxDeposit(alice), 0);
                assertEq(shares.maxMint(alice), 0);
                deal(address(asset), alice, 1 ether);
                vm.startPrank(alice);
                asset.approve(manifest.vault, 1 ether);
                vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
                shares.deposit(1, alice);
                vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
                shares.mint(1, alice);
                vm.stopPrank();
            }
            _executeCorrection(); // The matching positive cap is actually reset by the generated file.
            _assertClosedAllocation();
            assertEq(vault.quarantinedAssets(manifest.markets[0]), 0);
            assertEq(vault.quarantinedAssets(manifest.markets[1]), 0);
            assertEq(shares.maxWithdraw(alice), 1_000 ether);
            _generate();
            _assertNoCalldata();
            manifest.maxTemporaryCapAssets = 2; // Completed targets still consume the declared budget of 3.
            _expectPreparationRevert("Batch B: combined recovery cap limit exceeded");
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Omits one open recovery cap from the selected list, before and after permissionless acceptance.
    /// Rejects the incomplete selection; restoring all targets permits execution and closes every selected cap.
    function testBatchBRecoveryRejectsUnselectedPendingOrAcceptedCaps() public {
        _startBatchB();
        _quarantine(_firstTwo());
        _submitRecovery(_firstTwo());
        _matureRecovery();
        manifest.recoveryTargets.pop();
        _expectPreparationRevert("Batch B: allocation capacity remains");
        vault.acceptCap(manifest.markets[1]);
        _expectPreparationRevert("Batch B: allocation capacity remains");
        _selectRecovery(_firstTwo());
        _executeCorrection();
    }

    /// @dev Uses an accepted cap differing from approval, then a zero-cap recovered market with a pending removal.
    /// Rejects both conflicting states without preparing recovery calls or altering the existing position.
    function testBatchBRecoveryConflictingAcceptedCapAndPendingRemovalAreRejected() public {
        _startBatchB();
        _quarantine(_oneAddress(manifest.markets[0]));
        _submitRecovery(_oneAddress(manifest.markets[0]));
        _matureRecovery();
        vault.acceptCap(manifest.markets[0]);
        manifest.recoveryTargets[0].recoveryCap = 2;
        manifest.recoveryTargets[0].maxTemporaryCapAssets = 2;
        manifest.maxTemporaryCapAssets = 2;
        _expectPreparationRevert("Batch B: unexpected accepted cap");
        manifest.recoveryTargets[0].recoveryCap = 1;
        vm.startPrank(manifest.curatorSafe);
        vault.submitCap(manifest.markets[0], 0);
        vault.submitMarketRemoval(manifest.markets[0]);
        vm.stopPrank();
        _expectPreparationRevert("Batch B: recovery market removal pending");
    }

    /// @dev Varies recovery parameters across zero, per-market overflow, uint184 overflow and combined-budget excess.
    /// Rejects each invalid bound before any cap submission; the quarantined inventory remains unchanged.
    function testBatchBRecoveryCapLimitsArePositiveBoundedAndAggregate() public {
        _startBatchB();
        _quarantine(_firstTwo());
        _selectRecovery(_firstTwo());
        manifest.action = Action.SUBMIT_RECOVERY_CAP;
        manifest.recoveryTargets[0].recoveryCap = 0;
        _expectPreparationRevert("Batch B: recovery cap exceeds limit");
        manifest.recoveryTargets[0].recoveryCap = 2;
        _expectPreparationRevert("Batch B: recovery cap exceeds limit");
        manifest.recoveryTargets[0].recoveryCap = uint256(type(uint184).max) + 1;
        manifest.recoveryTargets[0].maxTemporaryCapAssets = manifest.recoveryTargets[0].recoveryCap;
        _expectPreparationRevert("Batch B: recovery cap overflows");
        _selectRecovery(_firstTwo());
        manifest.maxTemporaryCapAssets = 2;
        _expectPreparationRevert("Batch B: combined recovery cap limit exceeded");
    }

    /// @dev Varies one target's registration, controlled asset getter, quarantine history and listed allocator permission.
    /// Rejects each failed prerequisite; restoring eligibility permits a generated submission with the approved pending cap.
    function testBatchBRecoveryRequiresRegistryAssetHistoryAndRevokedAllocators() public {
        _startBatchB();
        _quarantine(_oneAddress(manifest.markets[0]));
        _selectRecovery(_oneAddress(manifest.markets[0]));
        manifest.action = Action.SUBMIT_RECOVERY_CAP;
        vm.prank(Ownable(address(registry)).owner());
        registry.removeBorrowMarket(manifest.markets[0]);
        _expectPreparationRevert("Batch B: recovery needs registered market");
        vm.prank(Ownable(address(registry)).owner());
        registry.addBorrowMarket(manifest.markets[0]);
        address wrongAsset = IMarket(manifest.markets[0]).collateralToken();
        vm.mockCall(
            manifest.markets[0], abi.encodeWithSelector(IMarketBase.borrowToken.selector), abi.encode(wrongAsset)
        );
        _expectPreparationRevert("Batch B: inconsistent market asset");
        vm.clearMockedCalls();
        delete manifest.quarantinedMarkets;
        _expectPreparationRevert("Batch B: missing quarantine history");
        manifest.quarantinedMarkets = _oneAddress(manifest.markets[0]);
        vm.prank(address(timelock));
        vault.setIsAllocator(revokedAllocator, true);
        _expectPreparationRevert("Batch B: nonessential allocator remains");
        vm.prank(address(timelock));
        vault.setIsAllocator(revokedAllocator, false);
        _executeCorrection();
    }

    /// @dev Uses a recovery-submission manifest pointing at an enabled market, then an unauthorized curator.
    /// Rejects both cases without creating a recovery cap or changing funded market state.
    function testBatchBRecoverySubmissionRequiresDisabledMarketAndCorrectCurator() public {
        _startBatchB();
        _selectRecovery(_oneAddress(manifest.markets[0]));
        manifest.quarantinedMarkets = _oneAddress(manifest.markets[0]);
        manifest.action = Action.SUBMIT_RECOVERY_CAP;
        _expectPreparationRevert("Batch B: recovery needs disabled market");
        manifest.curatorSafe = makeAddr("wrong curator");
        _expectPreparationRevert("ERP: unauthorized curator Safe");
    }

    /// @dev Prepares two mature recoveries, then deregisters the second target before Safe execution.
    /// The entire real Safe batch rolls back; restoring registration lets the same generated acceptance/reset work succeed.
    function testBatchBRecoveryAtomicSafeRollsBackEarlierPairsIfLaterAcceptanceFails() public {
        _startBatchB();
        _quarantine(_firstTwo());
        _submitRecovery(_firstTwo());
        _matureRecovery();
        _generate();
        bytes32 beforeClaims = _claimsHash();
        uint256 beforeLast = vault.lastTotalAssets();
        uint256 beforeLost = vault.lostAssets();
        uint256 pendingAt = vault.pendingCap(manifest.markets[0]).validAt;
        // A registry change after preparation invalidates only the second acceptance.
        vm.prank(Ownable(address(registry)).owner());
        registry.removeBorrowMarket(manifest.markets[1]);
        bytes memory execution = _signedCuratorExecution();
        (bool ok,) = manifest.curatorSafe.call(execution);
        assertFalse(ok, "Safe should roll back the entire generated MultiSend");
        assertEq(_claimsHash(), beforeClaims);
        assertEq(vault.lastTotalAssets(), beforeLast);
        assertEq(vault.lostAssets(), beforeLost);
        assertEq(vault.pendingCap(manifest.markets[0]).validAt, pendingAt);
        assertEq(vault.config(manifest.markets[0]).cap, 0);
        vm.prank(Ownable(address(registry)).owner());
        registry.addBorrowMarket(manifest.markets[1]);
        _executeCuratorAtomic();
        _assertClosedAllocation();
    }

    /// @dev Uses nearly full queues at submission, at acceptance, and with one target already enabled.
    /// Rejects aggregate overflow; only still-disabled targets consume new slots and the valid batch fills the queue exactly.
    function testBatchBRecoveryCapacityAtSubmissionAcceptanceAndPartialCompletion() public {
        _startBatchB();
        _quarantine(_firstTwo());
        // Cases: submission overflow, acceptance overflow, one target already enabled.
        for (uint256 state; state < 3; ++state) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += state;
            if (state == 0) {
                _fillQueueTo(29);
                _selectRecovery(_firstTwo());
                manifest.action = Action.SUBMIT_RECOVERY_CAP;
                _expectPreparationRevert("Batch B: withdrawal queue full");
            } else {
                _submitRecovery(_firstTwo());
                _fillQueueTo(state == 1 ? 29 : 28);
                manifest.action = Action.ACCEPT_RECOVERY_CAP;
                if (state == 1) {
                    _expectPreparationRevert("Batch B: withdrawal queue full");
                } else {
                    vault.acceptCap(manifest.markets[0]);
                    _executeCorrection();
                    assertEq(vault.withdrawQueueLength(), ConstantsLib.MAX_QUEUE_LENGTH);
                    _assertClosedAllocation();
                    _generate();
                    _assertNoCalldata();
                }
            }
            assertTrue(vm.revertToState(snapshot));
        }
    }

    // Accounting scenarios use real market state transitions, including separately authorized market loss treatment.

    /// @dev Uses controlled external governance loss treatment leaving half or none of one quarantined market's assets.
    /// Executes recovery through the shared accounting scenario; only recovered assets reduce loss and claims remain recorded.
    function testBatchBPartialAndZeroRecoveryPreserveUnrecoveredLoss() public {
        for (uint256 loss = 300 ether; loss <= 600 ether; loss += 300 ether) {
            uint256 snapshot = vm.snapshotState();
            _recoveryAfterMarketLoss(loss);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses one quarantined target and a separate market loss created by external governance treatment.
    /// Executes the target's recovery; its quarantine clears while the unrelated loss remains in Vault accounting.
    function testBatchBRecoveryCannotClearUnrelatedMarketLoss() public {
        _startBatchB();
        _quarantine(_oneAddress(manifest.markets[0]));
        address borrower = _borrow(manifest.markets[1], 100 ether);
        IMarket(manifest.markets[1]).governanceLiquidate(borrower, false);
        _submitRecovery(_oneAddress(manifest.markets[0]));
        _matureRecovery();
        _executeCorrection();
        assertEq(vault.lostAssets(), 100 ether);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 0);
        assertEq(vault.lastTotalAssets(), 1_000 ether);
    }

    /// @dev Uses approved quarantine recovery after a donation either increases target assets or reduces loss through a retained market.
    /// Executes the generated Safe batch in each state; recovery is bounded by recorded quarantine/loss and accounts for donations.
    function testBatchBRecoveryBoundsLossRecognitionAfterTargetOrRetainedMarketDonations() public {
        _startBatchB();
        _quarantine(_oneAddress(manifest.markets[0]));
        // Cases: assets grow inside the quarantined target, or in a retained market that offsets calculated loss.
        for (uint256 marketIndex; marketIndex < 2; ++marketIndex) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += marketIndex;
            uint256 donation = marketIndex == 0 ? 100 ether : 400 ether;
            _supplyOnBehalf(manifest.markets[marketIndex], donation, manifest.vault);
            _submitRecovery(_oneAddress(manifest.markets[0]));
            _matureRecovery();
            _executeCorrection();
            assertEq(vault.lostAssets(), 0);
            assertEq(vault.lastTotalAssets(), 1_000 ether + donation);
            assertEq(shares.totalAssets(), 1_000 ether + donation);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses a contained market whose liquidity is fully borrowed and a valid reordered queue.
    /// Executes the reorder and reports before/after repayment; time alone restores no liquidity, while repayment raises exit capacity.
    function testBatchBNoRepaymentAndLaterRepaymentChangeReportedExitAvailability() public {
        _startBatchB();
        address borrower = _borrow(manifest.markets[0], 600 ether);
        _reverseFundedQueue();
        _executeCorrection();
        assertEq(_reportAmount(".markets[0].totalBorrowAssets"), 600 ether);
        assertEq(_reportAmount(".markets[0].estimatedAvailableLiquidity"), 0);
        assertEq(shares.maxWithdraw(alice), 400 ether);
        vm.warp(block.timestamp + 30 days);
        _generate();
        _assertNoCalldata();
        assertEq(shares.maxWithdraw(alice), 400 ether);
        vm.startPrank(borrower);
        asset.approve(manifest.markets[0], 200 ether);
        IMarket(manifest.markets[0]).repay(200 ether, 0, borrower);
        vm.stopPrank();
        _advanceSourceBlock();
        _generate();
        assertEq(_reportAmount(".markets[0].totalBorrowAssets"), 400 ether);
        assertEq(_reportAmount(".markets[0].estimatedAvailableLiquidity"), 200 ether);
        assertEq(_reportAmount(".shareholders[0].maxWithdraw"), 600 ether);
        assertEq(shares.maxWithdraw(alice), 600 ether);
    }

    /// @dev Uses a real public liquidation after a controlled price shock, with bad debt outside the Vault ERP's actions.
    /// Executes a queue update and withdrawal; reports/accounting recognize loss while market shares and controls remain.
    function testBatchBOrdinaryLiquidationBadDebtChangesAccountingWithoutRemovingClaims() public {
        _startBatchB();
        address market = manifest.markets[0];
        address borrower = _borrow(market, 600 ether);
        // External fixture configuration: a public full liquidation with no incentive/protocol fee.
        LiquidationConfiguration memory config;
        config.maxLiquidationLtv = IMarket(market).maxLtv();
        config.ltvForCompleteLiquidation = config.maxLiquidationLtv;
        config.dynamicBonusFeeDecaySteepness = 5 ether;
        DlbDcfPriorityLiquidationEngine(IMarket(market).liquidationEngine()).setLiquidationConfiguration(config);
        OracleMock(IMarket(market).oracle()).setPrice(LENDING_ORACLE_PRICE_PRECISION / 20);
        uint256 positionBefore = IMarket(market).position(manifest.vault).supplyShares;
        deal(address(asset), address(this), 600 ether);
        asset.approve(market, 600 ether);
        IMarket(market).liquidate(borrower, "", "");
        assertEq(IMarket(market).position(borrower).borrowShares, 0);
        assertEq(IMarket(market).position(manifest.vault).supplyShares, positionBefore);
        assertEq(market.expectedSupplyAssets(manifest.vault), 300 ether);
        bytes32 controls = _controlsHash();
        _reverseFundedQueue();
        _executeCorrection();
        assertEq(_reportAmount(".markets[0].totalSupplyAssets"), 300 ether);
        assertEq(_reportAmount(".markets[0].totalBorrowAssets"), 0);
        assertEq(_reportAmount(".calculatedLostAssets"), 300 ether);
        assertEq(shares.maxWithdraw(alice), 700 ether);
        assertTrue(vault.config(market).enabled);
        vm.prank(alice);
        shares.withdraw(100 ether, alice, alice);
        assertEq(vault.lostAssets(), 300 ether);
        assertEq(_controlsHash(), controls);
    }

    /// @dev Uses paused and frozen funded markets with a controlled underlying-token shortage.
    /// Executes a queue update and the available exit; liquidity reports are bounded and both funded positions remain represented.
    function testBatchBPausedFrozenAndTokenLimitedMarketsRemainRepresented() public {
        _startBatchB();
        IMarket(manifest.markets[0]).pause(PAUSE_TYPE, true);
        IMarket(manifest.markets[1]).pause(FROZEN_TYPE, true);
        deal(address(asset), manifest.markets[1], 50 ether);
        bytes32 controls = _controlsHash();
        _reverseFundedQueue();
        _executeCorrection();
        assertEq(_reportAmount(".markets[0].estimatedAvailableLiquidity"), 0);
        assertEq(_reportAmount(".markets[1].estimatedAvailableLiquidity"), 50 ether);
        assertEq(_reportAmount(".shareholders[0].maxWithdraw"), 50 ether);
        assertEq(_reportAmount(".shareholders[0].maxRedeem"), shares.maxRedeem(alice));
        vm.prank(alice);
        shares.withdraw(50 ether, alice, alice);
        assertEq(asset.balanceOf(alice), 50 ether);
        assertEq(shares.maxWithdraw(alice), 0);
        assertTrue(vault.config(manifest.markets[0]).enabled);
        assertTrue(vault.config(manifest.markets[1]).enabled);
        assertEq(_controlsHash(), controls);
    }

    /// @dev Uses an unchanged queue under each severity, with valid notice and no executable work.
    /// Checks all nominal checkpoint dates and confirms reporting generates no transaction or step-history requirement.
    function testBatchBCheckpointDatesMatchEachSeverityAndHaveNoExecutionHistory() public {
        _startBatchB();
        for (uint256 severity; severity < 3; ++severity) {
            manifest.severity = Severity(severity);
            _generate();
            uint256[] memory times =
                vm.parseJsonUintArray(vm.readFile(_path("exposure-report.json")), ".checkpointTimestamps");
            if (severity < 2) {
                uint256[6] memory offsets =
                    severity == 0 ? [uint256(0), 1, 7, 14, 21, 28] : [uint256(0), 1, 4, 7, 10, 14];
                assertEq(times.length, 6);
                for (uint256 i; i < times.length; ++i) {
                    assertEq(times[i], manifest.t0 + offsets[i] * 1 days);
                }
            } else {
                assertEq(times.length, 8);
                for (uint256 i; i < times.length; ++i) {
                    assertEq(times[i], manifest.t0 + i * 1 days);
                }
            }
            _assertNoCalldata();
        }
    }

    /// @dev Keeps a prepared queue transaction, then monitors a manifest with a future T0 and no notice.
    /// Monitoring still reports source state and checkpoint dates while leaving the prepared transaction artifact untouched.
    function testBatchBReportsRemainAvailableBeforeNoticeAndDoNotDeleteTransactions() public {
        _startBatchB();
        _reverseFundedQueue();
        _generate();
        string memory path = _path("vault-allocator.json");
        string memory reviewed = vm.readFile(path);
        manifest.t0 = block.timestamp + 30 days;
        manifest.noticeAt = 0;
        _writeManifest();
        script.monitor(manifestPath, false);
        assertEq(vm.readFile(path), reviewed);
        string memory reportPath = string.concat(
            _testRoot(),
            "/monitor/step-",
            vm.toString(manifest.step),
            "/source-block-",
            vm.toString(manifest.sourceBlock),
            "/exposure-report.json"
        );
        string memory report = vm.readFile(reportPath);
        assertEq(vm.parseJsonUint(report, ".sourceBlock"), block.number);
        assertEq(vm.parseJsonUint(report, ".sourceTimestamp"), block.timestamp);
        assertEq(vm.parseJsonString(report, ".liquidityLabel"), "estimated available; not reserved or guaranteed");
        assertEq(vm.parseJsonUintArray(report, ".checkpointTimestamps")[5], manifest.t0 + 28 days);
    }

    /// @dev Varies every exceptional action's selected list across empty, malformed, zero, duplicate and out-of-scope targets.
    /// Rejects each invalid manifest without preparing executable work or changing Vault state.
    function testBatchBMalformedSelectedListsAndTargetScopeAreRejected() public {
        _startBatchB();
        _selectRemoval(_firstTwo());
        _selectRecovery(_firstTwo());
        for (uint256 action = 1; action < 5; ++action) {
            manifest.action = Action(action);
            string memory key = action <= 2 ? ".removalTargets" : ".recoveryTargets";
            _writeManifest();
            vm.writeJson("[]", manifestPath, key);
            _expectScriptRevert("ERP manifest: no action targets");
            _writeManifest();
            vm.writeJson("[{}]", manifestPath, key);
            _expectScriptRevert("");
            manifest.removalTargets[0].market = address(0);
            manifest.recoveryTargets[0].market = address(0);
            _expectPreparationRevert("Batch B: zero action market");
            manifest.removalTargets[0].market = makeAddr("outside target");
            manifest.recoveryTargets[0].market = makeAddr("outside target");
            _expectPreparationRevert("Batch B: action market outside scope");
            manifest.removalTargets[0].market = manifest.markets[0];
            manifest.recoveryTargets[0].market = manifest.markets[0];
            manifest.removalTargets[1].market = manifest.markets[0];
            manifest.recoveryTargets[1].market = manifest.markets[0];
            _expectPreparationRevert("Batch B: duplicate action market");
            manifest.removalTargets[1].market = manifest.markets[1];
            manifest.recoveryTargets[1].market = manifest.markets[1];
        }
    }

    /// @dev Uses an ordinary reorder with malformed inactive target lists, then a valid exceptional-removal manifest.
    /// Executes the reorder and checks copied exact approvals; only parameters relevant to the selected action are parsed.
    function testBatchBParsesOnlySelectedActionInputsAndRetainsExactApprovals() public {
        _startBatchB();
        _reverseFundedQueue();
        _writeManifest();
        vm.writeJson("[{}]", manifestPath, ".removalTargets");
        vm.writeJson("[{}]", manifestPath, ".recoveryTargets");
        script.run(1, manifestPath);
        _executeAllocator();
        assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.withdrawQueue);
        _readyRemoval(_firstTwo());
        _generate();
        assertEq(vm.readFile(_path("inputs.json")), vm.readFile(manifestPath));
        assertEq(
            vm.parseJsonUint(vm.readFile(_path("inputs.json")), ".removalTargets[0].approvedSupplyShares"),
            IMarket(manifest.markets[0]).position(manifest.vault).supplyShares
        );
        _executeAllocator();
        assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.withdrawQueue);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 600 ether);
        assertEq(vault.quarantinedAssets(manifest.markets[1]), 400 ether);
    }

    /// @dev Keeps a queue-plan artifact while a different action submits removals, reruns as a no-op and receives malformed targets.
    /// Checks selected-directory cleanup and preservation of the independently prepared queue artifact.
    function testBatchBFailureAndNoOpClearOnlySelectedActionDirectory() public {
        _startBatchB();
        _reverseFundedQueue();
        _generate();
        string memory queuePath = _path("vault-allocator.json");
        string memory queueJson = vm.readFile(queuePath);
        _selectRemoval(_firstTwo());
        manifest.action = Action.SUBMIT_REMOVAL;
        _generate();
        string memory removalPath = _path(CURATOR_FILE);
        _executeCuratorAtomic();
        _generate();
        assertFalse(vm.exists(removalPath));
        assertEq(vm.readFile(queuePath), queueJson);
        vm.writeFile(removalPath, "stale");
        _writeManifest();
        vm.writeJson("[]", manifestPath, ".removalTargets");
        _expectScriptRevert("ERP manifest: no action targets");
        assertFalse(vm.exists(removalPath));
        assertFalse(vm.exists(_path("exposure-report.json")));
        assertEq(vm.readFile(queuePath), queueJson);
    }

    // Helpers keep manifest construction separate from execution; response calldata is always read from disk.

    function _startBatchB() private {
        _useFixture();
        _completeBatchA();
        phase = Phase.BATCH_B_CORRECT;
        manifest.action = Action.UPDATE_WITHDRAW_QUEUE;
        manifest.t0 = block.timestamp;
        manifest.noticeAt = manifest.t0 - 7 days;
        manifest.allocator = retainedAllocator;
        manifest.withdrawQueue = ERPVaultQueue.withdrawQueue(vault);
    }

    function _executeCorrection() private {
        _advanceSourceBlock();
        _generate();
        _executePrepared();
        if (manifest.action == Action.UPDATE_WITHDRAW_QUEUE || manifest.action == Action.EXECUTE_REMOVAL) {
            assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.withdrawQueue);
        }
        for (uint256 i; i < manifest.removalTargets.length; ++i) {
            address market = manifest.removalTargets[i].market;
            if (manifest.action == Action.SUBMIT_REMOVAL) {
                assertGt(vault.config(market).removableAt, 0);
            } else if (manifest.action == Action.EXECUTE_REMOVAL) {
                assertFalse(vault.config(market).enabled);
                assertEq(vault.quarantinedAssets(market), manifest.removalTargets[i].approvedExpectedAssets);
            }
        }
        for (uint256 i; i < manifest.recoveryTargets.length; ++i) {
            address market = manifest.recoveryTargets[i].market;
            if (manifest.action == Action.SUBMIT_RECOVERY_CAP) {
                assertEq(vault.pendingCap(market).value, manifest.recoveryTargets[i].recoveryCap);
                assertGt(vault.pendingCap(market).validAt, block.timestamp);
            } else if (manifest.action == Action.ACCEPT_RECOVERY_CAP) {
                assertTrue(vault.config(market).enabled);
                assertEq(vault.config(market).cap, 0);
                assertEq(vault.pendingCap(market).validAt, 0);
                assertEq(vault.quarantinedAssets(market), 0);
            }
        }
    }

    function _selectRemoval(address[] memory targets) private {
        delete manifest.removalTargets;
        manifest.maxExceptionalRemovedAssets = 0;
        manifest.maxQuarantinedAssets = 0;
        for (uint256 i; i < targets.length; ++i) {
            uint256 assets = targets[i].expectedSupplyAssets(manifest.vault);
            manifest.removalTargets
                .push(
                    VaultOffboardingRemovalTarget(
                        assets, IMarket(targets[i]).position(manifest.vault).supplyShares, targets[i], assets
                    )
                );
            manifest.maxExceptionalRemovedAssets += assets;
        }
        manifest.maxQuarantinedAssets = manifest.maxExceptionalRemovedAssets;
        for (uint256 i; i < manifest.markets.length; ++i) {
            manifest.maxQuarantinedAssets += vault.quarantinedAssets(manifest.markets[i]);
        }
        manifest.maxLostAssets = shares.totalAssets();
    }

    function _readyRemoval(address[] memory targets) private {
        _selectRemoval(targets);
        manifest.action = Action.SUBMIT_REMOVAL;
        _executeCorrection();
        uint256 ready;
        for (uint256 i; i < targets.length; ++i) {
            ready = Math.max(ready, vault.config(targets[i]).removableAt);
        }
        vm.warp(ready);
        _advanceSourceBlock();
        _selectRemoval(targets);
        manifest.action = Action.EXECUTE_REMOVAL;
        delete manifest.withdrawQueue;
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            address market = vault.withdrawQueue(i);
            if (!ERPVaultQueue.contains(targets, market)) manifest.withdrawQueue.push(market);
        }
    }

    function _quarantine(address[] memory targets) private {
        _readyRemoval(targets);
        _executeCorrection();
        for (uint256 i; i < targets.length; ++i) {
            manifest.quarantinedMarkets.push(targets[i]);
        }
        _advanceSourceBlock();
    }

    function _selectRecovery(address[] memory targets) private {
        delete manifest.recoveryTargets;
        manifest.maxTemporaryCapAssets = 0;
        for (uint256 i; i < targets.length; ++i) {
            manifest.recoveryTargets.push(VaultOffboardingRecoveryTarget(targets[i], i + 1, i + 1));
            manifest.maxTemporaryCapAssets += i + 1;
        }
    }

    function _submitRecovery(address[] memory targets) private {
        _selectRecovery(targets);
        manifest.action = Action.SUBMIT_RECOVERY_CAP;
        _executeCorrection();
        _advanceSourceBlock();
    }

    function _matureRecovery() private {
        uint256 ready;
        for (uint256 i; i < manifest.recoveryTargets.length; ++i) {
            ready = Math.max(ready, vault.pendingCap(manifest.recoveryTargets[i].market).validAt);
        }
        vm.warp(ready);
        _advanceSourceBlock();
        manifest.action = Action.ACCEPT_RECOVERY_CAP;
    }

    function _fillQueueTo(uint256 length) private {
        address implementation = address(new AltoBorrowMarket());
        uint256 needed = length - vault.withdrawQueueLength();
        address[] memory added = new address[](needed);
        for (uint256 i; i < needed; ++i) {
            added[i] = _deployFixtureMarket(IMarket(manifest.markets[0]), implementation);
            manifest.markets.push(added[i]);
            vm.prank(manifest.curatorSafe);
            vault.submitCap(added[i], 1);
        }
        vm.warp(block.timestamp + vault.timelock());
        for (uint256 i; i < needed; ++i) {
            vault.acceptCap(added[i]);
            vm.prank(manifest.curatorSafe);
            vault.submitCap(added[i], 0);
        }
        _advanceSourceBlock();
    }

    function _recoveryAfterMarketLoss(uint256 loss) private {
        _startBatchB();
        manifest.step += loss / 1 ether;
        address market = manifest.markets[0];
        _quarantine(_oneAddress(market));
        uint256 positionBefore = IMarket(market).position(manifest.vault).supplyShares;
        address borrower = _borrow(market, loss);
        // A separate market-governance action realizes loss. Vault ERP must recognize it, never generate this action.
        IMarket(market).governanceLiquidate(borrower, false);
        assertEq(IMarket(market).position(manifest.vault).supplyShares, positionBefore);
        uint256 liveAssets = market.expectedSupplyAssets(manifest.vault);
        assertEq(liveAssets, 600 ether - loss);
        vm.prank(alice);
        shares.withdraw(0, alice, alice);
        assertEq(vault.lostAssets(), 600 ether);
        _submitRecovery(_oneAddress(market));
        _matureRecovery();
        _executeCorrection();
        assertEq(vault.lostAssets(), loss);
        assertEq(vault.lastTotalAssets(), 1_000 ether);
        assertEq(vault.quarantinedAssets(market), 0);
        assertTrue(vault.config(market).enabled);
        assertEq(shares.totalSupply(), 1_000 ether);
        assertEq(shares.maxWithdraw(alice), 1_000 ether - loss);
        _assertClosedAllocation();
    }

    function _controlsHash() private view returns (bytes32 hash) {
        hash = keccak256(
            abi.encode(
                _marketControlsHash(),
                vault.curator(),
                vault.guardian(),
                Ownable(manifest.vault).owner(),
                adapter.isApprovedContract(manifest.vault),
                IVaultRegistry(contracts.vaultRegistry).isVault(manifest.vault)
            )
        );
    }

    function _positionShares() private view returns (uint256[] memory values) {
        values = new uint256[](manifest.markets.length);
        for (uint256 i; i < values.length; ++i) {
            values[i] = IMarket(manifest.markets[i]).position(manifest.vault).supplyShares;
        }
    }

    function _reverseFundedQueue() private {
        manifest.withdrawQueue = manifest.markets;
        manifest.withdrawQueue[0] = manifest.markets[1];
        manifest.withdrawQueue[1] = manifest.markets[0];
    }

    function _firstTwo() private view returns (address[] memory targets) {
        targets = new address[](2);
        targets[0] = manifest.markets[0];
        targets[1] = manifest.markets[1];
    }
}
