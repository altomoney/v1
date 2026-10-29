// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultOffboardingTestBase} from "./VaultOffboardingTestBase.sol";
import {
    VaultOffboardingPhase as Phase,
    VaultOffboardingAction as Action,
    VaultOffboardingRecoveryTarget,
    VaultOffboardingSeverity as Severity,
    VaultOffboardingToken,
    VaultOffboardingClosureMarket
} from "../IVaultOffboarding.sol";
import {ERPVaultQueue} from "../../libraries/ERPVaultQueue.sol";
import {IAltoVaultErrors} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

/// @dev Spec: ERP-OFFBOARD-03, Batch C ordering/targets and acceptance criteria.
/// Response execution uses production-script JSON and the real governance Timelock.
/// Exceptional references identify external evidence; tests do not certify claim settlement or governance approval.
contract BatchCRecoverTest is VaultOffboardingTestBase {
    using AltoBalancesLib for address;
    using stdStorage for StdStorage;

    function setUp() public {
        _setUpFork();
    }

    function _activationId() internal pure override returns (string memory) {
        return "test-vault-batch-c";
    }

    // Ordinary closure requires final shareholder redemption and reconciled positions/accounting.

    /// @dev Uses ordinary zero-claims closure with approved tokens, listed allocators and matured administrative/removal changes.
    /// Executes queue/token/role cleanup, then delayed integration removal; empty configurations clear and governance ownership remains.
    function testBatchCOrdinaryCleanupThenDelayedIntegrationRemovalFromGeneratedFiles() public {
        _startRecovery(true);
        address recipient = makeAddr("approved token recipient");
        _seedTokens(recipient, makeAddr("other token recipient"));
        _seedAdministrativeChanges();
        vm.warp(block.timestamp + vault.timelock()); // Even matured removal permissions are revoked before omission.
        manifest.allocatorsToRevoke.push(retainedAllocator);
        bytes32 marketState = _marketControlsHash();
        uint256 sourceTime = block.timestamp;
        _generate();
        _assertOutcome("full-cleanup-prepared");
        assertEq(_reportAmount(".tokens[0].balance"), 7 ether);
        assertEq(vm.parseJsonUint(vm.readFile(_path("exposure-report.json")), ".sourceTimestamp"), sourceTime);
        assertEq(vm.readFile(_path("inputs.json")), vm.readFile(manifestPath));
        assertFalse(vm.exists(_path(CURATOR_FILE)));
        assertFalse(vm.exists(_path("vault-allocator.json")));
        _executeOwner();
        assertEq(asset.balanceOf(recipient), 7 ether);
        assertEq(IERC20(manifest.tokens[1].token).balanceOf(manifest.tokens[1].recipient), 11);
        assertEq(asset.balanceOf(manifest.vault), 0);
        assertEq(IERC20(manifest.tokens[1].token).balanceOf(manifest.vault), 0);
        assertEq(vault.curator(), address(0));
        assertEq(vault.guardian(), guardian);
        assertEq(vault.pendingGuardian().value, address(0));
        assertEq(vault.pendingGuardian().validAt, block.timestamp + vault.timelock());
        assertEq(vault.pendingTimelock().validAt, 0);
        assertFalse(vault.isAllocator(retainedAllocator));
        assertFalse(vault.isAllocator(revokedAllocator));
        assertEq(vault.skimRecipient(), address(0));
        assertEq(vault.feeRecipient(), address(0));
        _assertIntegrations(true);
        _assertOrdinaryZeroState();
        _advanceSourceBlock();
        _expectPreparationRevert("Batch C: guardian removal not ready");
        vm.warp(vault.pendingGuardian().validAt - 1);
        _expectPreparationRevert("Batch C: guardian removal not ready");
        vm.warp(vault.pendingGuardian().validAt);
        _advanceSourceBlock();
        _generate();
        _assertOutcome("integration-removal-prepared");
        _executeOwner();
        _assertIntegrations(false);
        assertEq(vault.guardian(), address(0));
        assertEq(vault.pendingGuardian().validAt, 0);
        assertEq(Ownable(manifest.vault).owner(), address(timelock));
        assertEq(_marketControlsHash(), marketState);
        _assertOrdinaryZeroState();
        _advanceSourceBlock();
        _generate();
        _assertNoCalldata();
        _assertOutcome("no-cleanup-required");
    }

    /// @dev Uses ordinary manifests with controlled stored/calculated loss, quarantine residue or a zero-asset supply-share dust claim.
    /// Rejects every residual case and retains recovery routes; historical accounting fixtures do not imply external settlement.
    function testBatchCOrdinaryClosureRejectsAccountingQuarantineAndShareDust() public {
        _startRecovery(true);
        // Cases: calculated loss, stored loss, supply-share dust, quarantine without shares.
        for (uint256 residue; residue < 4; ++residue) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += residue;
            if (residue < 2) {
                _setAccounting(10, residue == 0 ? 0 : 10);
                assertEq(shares.totalAssets(), 10);
                _expectPreparationRevert("Batch C: unresolved accounting");
            } else {
                if (residue == 2) {
                    deal(address(asset), address(this), 1);
                    asset.approve(manifest.markets[2], 1);
                    IMarket(manifest.markets[2]).addSupply(0, 1, manifest.vault);
                    assertEq(manifest.markets[2].expectedSupplyAssets(manifest.vault), 0);
                    assertEq(shares.totalAssets(), 0);
                } else {
                    _setQuarantine(manifest.markets[0], 1);
                }
                _expectPreparationRevert("Batch C: market claims remain");
            }
            _assertRecoveryRoutes();
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses a final redemption that leaves one unit of market dust, first ordinary then with exact exceptional approval.
    /// Rejects ordinary closure; exceptional partial cleanup retains the funded market and its recovery controls/integrations.
    function testBatchCFinalShareholderRoundingResidueKeepsMarketAndRecoveryRoutes() public {
        _startRecovery(false);
        _supplyOnBehalf(manifest.markets[0], 1, manifest.vault);
        _redeemAll();
        assertEq(shares.totalAssets(), 1);
        assertGt(IMarket(manifest.markets[1]).position(manifest.vault).supplyShares, 0);
        _expectPreparationRevert("Batch C: unresolved accounting");
        _approveCurrentResiduals();
        _executeStage();
        assertEq(vault.withdrawQueueLength(), 1);
        assertEq(vault.withdrawQueue(0), manifest.markets[1]);
        assertEq(manifest.markets[1].expectedSupplyAssets(manifest.vault), 1);
        _assertRecoveryRoutes();
    }

    /// @dev Uses an ordinary manifest after Batch A accrued fee shares and the main shareholder redeemed.
    /// Rejects closure because earned fee shares still represent claims, preserving their recipient and exit routes.
    function testBatchCEarnedFeeSharesRemainClaimsAfterFeeHasBeenStopped() public {
        _useFixture();
        _supplyOnBehalf(manifest.markets[0], 100 ether, manifest.vault);
        _completeBatchA();
        assertEq(vault.fee(), 0);
        assertGt(shares.balanceOf(feeRecipient), 0);
        uint256 userShares = shares.balanceOf(alice);
        vm.prank(alice);
        shares.redeem(userShares, alice, alice);
        phase = Phase.BATCH_C_RECOVER;
        manifest.tokens.push(VaultOffboardingToken(0, address(0), address(asset)));
        _advanceSourceBlock();
        _expectPreparationRevert("Batch C: shareholder claims remain");
        assertEq(vault.feeRecipient(), feeRecipient);
        _assertRecoveryRoutes();
    }

    /// @dev Uses a controlled historical external treatment fixture with empty market positions but unresolved Vault shares.
    /// Executes approved partial cleanup; empty queue entries clear, loss accrues and residual claims retain recovery routes.
    function testBatchCShareClaimsAloneKeepRolesAndIntegrationsAfterMarketPositionsAreZero() public {
        _startRecovery(false);
        // Historical external treatment fixture: market positions were redeemed, shareholder claims are unresolved.
        for (uint256 i; i < 2; ++i) {
            IMarket market = IMarket(manifest.markets[i]);
            uint256 position = market.position(manifest.vault).supplyShares;
            vm.prank(manifest.vault);
            market.removeSupply(0, position, manifest.vault, makeAddr("external settlement account"));
        }
        assertGt(shares.totalSupply(), 0);
        _approveCurrentResiduals();
        _executeStage();
        assertEq(vault.withdrawQueueLength(), 0);
        assertEq(vault.lostAssets(), 1_000 ether);
        _assertRecoveryRoutes();
        _approveCurrentResiduals();
        _generate();
        _assertOutcome("residual-claims");
        _assertNoCalldata();
    }

    /// @dev Uses an ordinary zero-claims manifest with paused/frozen empty markets.
    /// Executes staged cleanup and integration removal; market control settings remain unchanged.
    function testBatchCPausedAndFrozenEmptyMarketsDoNotBlockCleanupOrChangeMarketControls() public {
        _startRecovery(true);
        IMarket(manifest.markets[0]).pause(PAUSE_TYPE, true);
        IMarket(manifest.markets[1]).pause(FROZEN_TYPE, true);
        bytes32 controls = _marketControlsHash();
        _executeStage();
        _finishGuardianDelay();
        _generate();
        _executeOwner();
        _assertOrdinaryZeroState();
        _assertIntegrations(false);
        assertEq(_marketControlsHash(), controls);
    }

    /// @dev Varies both closure modes with remaining supply queue, fee, pending cap or accepted allocation capacity.
    /// Rejects incomplete containment; once closed, generated cleanup executes while integrations remain for the later stage.
    function testBatchCContainmentRequiredInOrdinaryAndExceptionalModes() public {
        _startRecovery(true);
        for (uint256 mode; mode < 2; ++mode) {
            if (mode == 1) _approveCurrentResiduals();
            vm.prank(manifest.curatorSafe);
            vault.submitCap(manifest.markets[0], 1);
            vm.warp(vault.pendingCap(manifest.markets[0]).validAt);
            vault.acceptCap(manifest.markets[0]);
            vm.prank(manifest.curatorSafe);
            vault.setSupplyQueue(_oneAddress(manifest.markets[0]));
            vm.prank(manifest.curatorSafe);
            vault.submitCap(manifest.markets[0], 0);
            _expectPreparationRevert("Batch C: containment incomplete");
            vm.prank(manifest.curatorSafe);
            vault.setSupplyQueue(new address[](0));
            vm.prank(address(timelock));
            vault.setFee(0.1 ether);
            _expectPreparationRevert("Batch C: containment incomplete");
            vm.prank(address(timelock));
            vault.setFee(0);
            vm.prank(manifest.curatorSafe);
            vault.submitCap(manifest.markets[0], 1);
            _expectPreparationRevert("Batch C: allocation capacity remains");
            vm.warp(vault.pendingCap(manifest.markets[0]).validAt);
            vault.acceptCap(manifest.markets[0]);
            _expectPreparationRevert("Batch C: allocation capacity remains");
            vm.prank(manifest.curatorSafe);
            vault.submitCap(manifest.markets[0], 0);
        }
        _executeStage();
        _assertOrdinaryZeroState();
        _assertIntegrations(true);
    }

    /// @dev Uses an ordinary zero-claims manifest missing an entry from the current withdrawal queue.
    /// Rejects incomplete inventory without clearing configurations or preparing cleanup transactions.
    function testBatchCRequiresCompleteCurrentQueueInventory() public {
        _startRecovery(true);
        manifest.markets.pop();
        _expectPreparationRevert("ERP: withdrawal market omitted");
    }

    /// @dev Uses ordinary closure by default, then every severity after the active window and a future T0 once shareholders exit.
    /// Claims still block closure; generated cleanup/removal succeeds only after the required guardian delay.
    function testBatchCNoSeverityOrElapsedPeriodBypassesClaimsAndGuardianDelay() public {
        _startRecovery(false);
        _writeManifest();
        vm.writeFile(manifestPath, vm.replace(vm.readFile(manifestPath), '"exceptionalClosure"', '"unusedFlag"'));
        _expectScriptRevert("Batch C: shareholder claims remain"); // Omission defaults to ordinary closure.
        vm.warp(block.timestamp + 365 days);
        _advanceSourceBlock();
        for (uint256 i; i < 3; ++i) {
            manifest.severity = Severity(i);
            _expectPreparationRevert("Batch C: shareholder claims remain");
        }
        _assertRecoveryRoutes();
        _redeemAll();
        // Batch C has state gates; a checkpoint or Batch B notice is not its execution gate.
        manifest.t0 = block.timestamp + 30 days;
        _executeStage();
        for (uint256 i; i < 3; ++i) {
            manifest.severity = Severity(i);
            _expectPreparationRevert("Batch C: guardian removal not ready");
        }
        _finishGuardianDelay();
        _generate();
        _executeOwner();
        _assertOrdinaryZeroState();
        _assertIntegrations(false);
    }

    // Skim is full-balance and recipient-specific. Its source approval is not an execution-time cap.

    /// @dev Varies the reviewed token list with missing underlying, invalid tokens, self-recipient or duplicate entries.
    /// Rejects each malformed treatment list without skimming tokens or changing cleanup state.
    function testBatchCRejectsInvalidTokenListsAndMissingUnderlying() public {
        _startRecovery(true);
        manifest.tokens.pop();
        _expectPreparationRevert("ERP manifest: underlying token omitted");
        manifest.tokens.push(VaultOffboardingToken(0, address(0), address(0)));
        _expectPreparationRevert("ERP manifest: invalid token treatment");
        manifest.tokens[0].token = manifest.vault;
        _expectPreparationRevert("ERP manifest: invalid token treatment");
        manifest.tokens[0].token = address(asset);
        manifest.tokens[0].recipient = manifest.vault;
        _expectPreparationRevert("ERP manifest: invalid token treatment");
        manifest.tokens[0].recipient = address(0);
        manifest.tokens.push(manifest.tokens[0]);
        _expectPreparationRevert("ERP manifest: duplicate token");
    }

    /// @dev Uses a nonzero underlying balance with approvals below/above it or an absent recipient.
    /// Rejects each treatment mismatch before preparing token transfers or changing the Vault's recipients.
    function testBatchCSkimRequiresExactNonzeroBalanceAndRecipient() public {
        _startRecovery(true);
        deal(address(asset), manifest.vault, 5 ether);
        manifest.tokens[0].recipient = makeAddr("approved recipient");
        manifest.tokens[0].approvedBalance = 4 ether;
        _expectPreparationRevert("Batch C: token treatment differs from approval");
        manifest.tokens[0].approvedBalance = 6 ether;
        _expectPreparationRevert("Batch C: token treatment differs from approval");
        manifest.tokens[0].approvedBalance = 5 ether;
        manifest.tokens[0].recipient = address(0);
        _expectPreparationRevert("Batch C: token treatment differs from approval");
    }

    /// @dev Varies approved token treatment with zero balances, a shared current recipient or permissionless skim before execution.
    /// Executes cleanup; available full balances reach recipients, the skim recipient clears and integrations remain staged.
    function testBatchCTokenCleanupHandlesZeroBalancesSharedRecipientAndPriorSkim() public {
        _startRecovery(true);
        // Cases: zero balance, common recipient for both tokens, one token already skimmed.
        for (uint256 state; state < 3; ++state) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += state;
            address recipient = vault.skimRecipient();
            if (state == 0) {
                manifest.tokens[0].approvedBalance = 123;
                manifest.tokens[0].recipient = address(0);
            } else {
                _seedTokens(recipient, recipient);
            }
            _generate();
            if (state == 2) vault.skim(address(asset)); // Permissionless skim between preparation and execution.
            _executeOwner();
            assertEq(asset.balanceOf(manifest.vault), 0);
            assertEq(asset.balanceOf(recipient), state == 0 ? 0 : 7 ether);
            if (state != 0) {
                assertEq(IERC20(manifest.tokens[1].token).balanceOf(recipient), 11);
                assertEq(IERC20(manifest.tokens[1].token).balanceOf(manifest.vault), 0);
            }
            assertEq(vault.skimRecipient(), address(0));
            _assertIntegrations(true);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Approves a source token balance that increases during the governance delay.
    /// Executes full-balance skim while retaining the original snapshot; fresh execution-time balance review remains external.
    function testBatchCSkimTransfersExecutionBalanceAndReportRemainsSourceSnapshot() public {
        _startRecovery(true);
        address recipient = makeAddr("approved recipient");
        deal(address(asset), manifest.vault, 5 ether);
        manifest.tokens[0] = VaultOffboardingToken(5 ether, recipient, address(asset));
        _generate();
        string memory snapshot = vm.readFile(_path("exposure-report.json"));
        bytes32 id = _scheduleOwner();
        // A fresh-state balance review is external: skim has no amount argument.
        deal(address(asset), manifest.vault, 6 ether);
        _executeSafeFile(EXECUTE_FILE, manifest.timelockSafe);
        assertTrue(timelock.isOperationDone(id));
        assertEq(asset.balanceOf(recipient), 6 ether);
        assertEq(_reportAmount(".tokens[0].balance"), 5 ether);
        assertEq(vm.readFile(_path("exposure-report.json")), snapshot);
        _assertIntegrations(true);
    }

    /// @dev Uses two approved token treatments and a controlled failure in the second token's transfer.
    /// Real Timelock execution rolls back all cleanup; removing the failure lets the same operation transfer both balances.
    function testBatchCTokenTransferFailureRollsBackEntireTimelockCleanup() public {
        _startRecovery(true);
        _seedTokens(makeAddr("first recipient"), makeAddr("second recipient"));
        _generate();
        bytes32 id = _scheduleOwner();
        bytes32 claimsBefore = _claimsHash();
        address skimBefore = vault.skimRecipient();
        // Inject a failing external token; the Vault and Timelock still execute their real implementations.
        vm.mockCall(
            manifest.tokens[1].token,
            abi.encodeCall(IERC20.transfer, (manifest.tokens[1].recipient, 11)),
            abi.encode(false)
        );
        _assertExecutionFails();
        assertTrue(timelock.isOperationReady(id));
        assertEq(_claimsHash(), claimsBefore);
        assertEq(asset.balanceOf(manifest.vault), 7 ether);
        assertEq(asset.balanceOf(manifest.tokens[0].recipient), 0);
        assertEq(vault.skimRecipient(), skimBefore);
        _assertRecoveryRoutes();
        vm.clearMockedCalls();
        _executeSafeFile(EXECUTE_FILE, manifest.timelockSafe);
        assertTrue(timelock.isOperationDone(id));
        _assertOrdinaryZeroState();
        assertEq(asset.balanceOf(manifest.tokens[0].recipient), 7 ether);
        assertEq(IERC20(manifest.tokens[1].token).balanceOf(manifest.tokens[1].recipient), 11);
    }

    // Queue revocations restore the protocol's funded-position protection throughout governance delays.

    /// @dev Prepares ordinary empty-market cleanup, then adds a funded position and matured removal permission during the delay.
    /// Execution revokes that permission before omission and reverts atomically, preserving the new claim and recovery routes.
    function testBatchCNewSupplyBeforeExecutionRejectsRemovalEvenWithMaturedPermission() public {
        _startRecovery(true);
        _generate();
        bytes32 id = _scheduleOwner();
        // The removal permission did not exist at preparation; unconditional revocation must still cancel it.
        vm.prank(manifest.curatorSafe);
        vault.submitMarketRemoval(manifest.markets[0]);
        vm.warp(vault.config(manifest.markets[0]).removableAt);
        _supplyOnBehalf(manifest.markets[0], 1 ether, manifest.vault);
        bytes32 claimsBefore = _claimsHash();
        (address target, bytes memory data) = _transaction(vm.readFile(_path(EXECUTE_FILE)), 0);
        vm.prank(manifest.timelockSafe);
        (bool ok, bytes memory reason) = target.call(data);
        assertFalse(ok);
        assertEq(
            reason,
            abi.encodeWithSelector(IAltoVaultErrors.InvalidMarketRemovalNonZeroSupply.selector, manifest.markets[0])
        );
        assertEq(_claimsHash(), claimsBefore);
        assertFalse(timelock.isOperationDone(id));
        _assertRecoveryRoutes();
    }

    /// @dev Uses exact exceptional approvals, an interleaved empty queue entry, matured changes and explicit nonessential allocators.
    /// Executes partial cleanup; funded order and essential roles/integrations remain, listed permissions clear and adapter exits work.
    function testBatchCPartialCleanupPreservesFundedOrderAndActualAdapterExits() public {
        _startRecovery(false);
        uint256[] memory order = new uint256[](3);
        order[0] = 1;
        order[1] = 2;
        order[2] = 0;
        vm.prank(manifest.curatorSafe);
        vault.updateWithdrawQueue(order);
        _seedAdministrativeChanges();
        vm.prank(address(timelock));
        vault.setIsAllocator(revokedAllocator, true);
        manifest.allocatorsToRevoke.push(makeAddr("already inactive allocator"));
        vm.prank(address(timelock));
        vault.submitGuardian(makeAddr("unwanted guardian"));
        vm.warp(block.timestamp + vault.timelock());
        _approveCurrentResiduals();
        bytes32 controls = _marketControlsHash();
        _generate();
        _assertOutcome("partial-cleanup-prepared");
        _executeOwner();
        assertEq(vault.withdrawQueueLength(), 2);
        assertEq(vault.withdrawQueue(0), manifest.markets[1]);
        assertEq(vault.withdrawQueue(1), manifest.markets[0]);
        assertFalse(vault.config(manifest.markets[2]).enabled);
        assertEq(shares.totalSupply(), 1_000 ether);
        assertEq(vault.pendingGuardian().validAt, 0);
        assertEq(vault.pendingTimelock().validAt, 0);
        assertEq(_marketControlsHash(), controls);
        assertFalse(vault.isAllocator(revokedAllocator));
        assertTrue(vault.isAllocator(retainedAllocator));
        _assertRecoveryRoutes();
        _withdrawThroughAdapter(100 ether);
        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(manifest.markets[1].expectedSupplyAssets(manifest.vault), 300 ether);
        assertEq(manifest.markets[0].expectedSupplyAssets(manifest.vault), 600 ether);
        _approveCurrentResiduals();
        _advanceSourceBlock();
        _generate();
        _assertNoCalldata();
        _assertOutcome("residual-claims");
    }

    /// @dev Uses exact exceptional approvals with every current queue entry funded.
    /// Executes permitted role/recipient cleanup while preserving the complete funded queue and recovery routes.
    function testBatchCPartialCleanupPreservesUnchangedFundedQueue() public {
        _startRecovery(false);
        _supplyOnBehalf(manifest.markets[2], 1 ether, manifest.vault);
        _approveCurrentResiduals();
        _generate();
        _executeOwner();
        assertEq(ERPVaultQueue.withdrawQueue(vault), manifest.markets);
        _assertRecoveryRoutes();
    }

    /// @dev Uses exceptional closure after a market donation creates a position while Vault shareholder supply is zero.
    /// Executes partial cleanup; the position retains its route and accrued accounting requires fresh approval on rerun.
    function testBatchCPartialCleanupRetainsRoutesForMarketPositionWithoutVaultShares() public {
        _startRecovery(true);
        _supplyOnBehalf(manifest.markets[0], 5 ether, manifest.vault);
        assertEq(shares.totalSupply(), 0);
        _approveCurrentResiduals();
        _executeStage();
        assertEq(vault.withdrawQueueLength(), 1);
        assertGt(IMarket(manifest.markets[0]).position(manifest.vault).supplyShares, 0);
        _assertRecoveryRoutes();
        // Fee-recipient cleanup accrued the newly donated market assets: old exact approvals must fail.
        _expectPreparationRevert("Batch C: accounting differs from approval");
        _approveCurrentResiduals();
        _generate();
        _assertNoCalldata();
        _assertOutcome("residual-claims");
    }

    /// @dev Uses a historical native quarantine with exact exceptional approvals before its loss has accrued.
    /// Executes partial cleanup; quarantine/position remain, stored loss updates and stale approvals reject subsequent preparation.
    function testBatchCQuarantinedPositionRetainsRoutesAndStoredLossRequiresFreshApproval() public {
        _startRecovery(false);
        _seedHistoricalQuarantine();
        assertEq(vault.lostAssets(), 0);
        _approveCurrentResiduals();
        _generate();
        uint256 position = IMarket(manifest.markets[0]).position(manifest.vault).supplyShares;
        _executeOwner();
        assertEq(vault.lostAssets(), 600 ether);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 600 ether);
        assertEq(IMarket(manifest.markets[0]).position(manifest.vault).supplyShares, position);
        assertFalse(vault.config(manifest.markets[0]).enabled);
        _assertRecoveryRoutes();
        _advanceSourceBlock();
        _expectPreparationRevert("Batch C: accounting differs from approval");
        _approveCurrentResiduals();
        _generate();
        _assertNoCalldata();
        _assertOutcome("residual-claims");
    }

    /// @dev Uses approved partial cleanup with a quarantined position and remaining shareholders.
    /// Returns to Batch B through real atomic Safe files, redeems claims, then completes delayed Batch C integration removal.
    function testBatchCPartialCleanupPreservesBatchBQuarantineRecoveryAndFinalExit() public {
        _startRecovery(false);
        _seedHistoricalQuarantine();
        _approveCurrentResiduals();
        _executeStage();
        _assertRecoveryRoutes();
        phase = Phase.BATCH_B_CORRECT;
        manifest.t0 = block.timestamp;
        manifest.noticeAt = block.timestamp - 7 days;
        manifest.action = Action.SUBMIT_RECOVERY_CAP;
        manifest.maxTemporaryCapAssets = 1;
        manifest.recoveryTargets.push(VaultOffboardingRecoveryTarget(manifest.markets[0], 1, 1));
        _generate();
        _executeCuratorAtomic();
        uint256 readyAt = vault.pendingCap(manifest.markets[0]).validAt;
        manifest.action = Action.ACCEPT_RECOVERY_CAP;
        _expectPreparationRevert("Batch B: recovery cap not ready");
        vm.warp(readyAt);
        _advanceSourceBlock();
        _generate();
        _executeCuratorAtomic();
        phase = Phase.BATCH_C_RECOVER;
        assertEq(vault.lostAssets(), 0);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 0);
        assertEq(vault.config(manifest.markets[0]).cap, 0);
        assertEq(shares.maxWithdraw(alice), 1_000 ether);
        _redeemAll();
        _approveCurrentResiduals();
        _executeStage();
        assertEq(vault.curator(), address(0));
        _assertIntegrations(true);
        _finishGuardianDelay();
        _generate();
        _executeOwner();
        _assertIntegrations(false);
    }

    /// @dev Uses exceptional partial cleanup while a pending guardian removal is already mature.
    /// Executes cleanup; pending removal is revoked so the current guardian and recovery routes remain available.
    function testBatchCPartialCleanupPreservesPendingGuardianRemovalOnlyByRevokingIt() public {
        _startRecovery(false);
        vm.prank(address(timelock));
        vault.submitGuardian(address(0));
        vm.warp(vault.pendingGuardian().validAt);
        _approveCurrentResiduals();
        _generate();
        _executeOwner();
        assertEq(vault.pendingGuardian().validAt, 0);
        _assertRecoveryRoutes();
    }

    // Exceptional approvals match every observed value; aggregate budgets do not replace exact approvals.

    /// @dev Uses exact residual approvals but omits the governance approval or treatment reference.
    /// Rejects missing references; external reviewers, rather than this script, establish the validity of the cited evidence.
    function testBatchCExceptionalRequiresBothEvidenceReferences() public {
        _startRecovery(false);
        _approveCurrentResiduals();
        manifest.closureApprovalReference = "";
        _expectPreparationRevert("Batch C: closure approval reference missing");
        manifest.closureApprovalReference = "governance approval";
        manifest.closureTreatmentReference = "";
        _expectPreparationRevert("Batch C: closure treatment reference missing");
    }

    /// @dev Changes each exact approved Vault total or per-market position/quarantine value one at a time.
    /// Rejects every mismatch while preserving recovery routes; aggregate limits do not substitute for exact source approvals.
    function testBatchCExceptionalRejectsEveryMismatchedResidualApproval() public {
        _startRecovery(false);
        for (uint256 field; field < 7; ++field) {
            _approveCurrentResiduals();
            if (field == 0) manifest.approvedTotalSupply++;
            else if (field == 1) manifest.approvedTotalAssets++;
            else if (field == 2) manifest.approvedLastTotalAssets++;
            else if (field == 3) manifest.approvedLostAssets++;
            else if (field == 4) manifest.closureMarkets[0].approvedSupplyShares++;
            else if (field == 5) manifest.closureMarkets[0].approvedExpectedAssets++;
            else manifest.closureMarkets[0].approvedQuarantinedAssets++;
            _expectPreparationRevert(
                field < 4
                    ? "Batch C: accounting differs from approval"
                    : "Batch C: market position differs from approval"
            );
            _assertRecoveryRoutes();
        }
    }

    /// @dev Varies exceptional closure inventory with missing, repeated, zero or unreviewed markets.
    /// Rejects each invalid inventory without changing positions or preparing cleanup transactions.
    function testBatchCExceptionalRejectsIncompleteDuplicateZeroAndOutOfScopeInventory() public {
        _startRecovery(false);
        _approveCurrentResiduals();
        manifest.closureMarkets.pop();
        _expectPreparationRevert("Batch C: closure inventory incomplete");
        _approveCurrentResiduals();
        manifest.closureMarkets[2].market = manifest.markets[0];
        _expectPreparationRevert("Batch C: duplicate closure market");
        manifest.closureMarkets[2].market = address(0);
        _expectPreparationRevert("Batch C: zero closure market");
        manifest.closureMarkets[2].market = makeAddr("outside scope");
        _expectPreparationRevert("Batch C: closure market outside scope");
    }

    /// @dev Uses complete exact exceptional approvals in a different order from the reviewed market list.
    /// Executes partial cleanup by market identity; empty entries clear while funded positions and recovery routes remain.
    function testBatchCExceptionalInventoryCanUseDifferentOrderFromReviewedMarkets() public {
        _startRecovery(false);
        _approveCurrentResiduals();
        VaultOffboardingClosureMarket memory first = manifest.closureMarkets[0];
        manifest.closureMarkets[0] = manifest.closureMarkets[2];
        manifest.closureMarkets[2] = first;
        _generate();
        _executeOwner();
        assertEq(vault.withdrawQueueLength(), 2);
        assertFalse(vault.config(manifest.markets[2]).enabled);
        _assertRecoveryRoutes();
    }

    /// @dev Uses controlled historical accounting and quarantine residues with exact approvals but varying aggregate limits.
    /// Rejects insufficient limits; allowed bounds execute cleanup and preserve the approved residue for the next stage.
    function testBatchCExceptionalBoundsStoredCalculatedLossAndAggregateQuarantine() public {
        _startRecovery(true);
        _setAccounting(30, 10);
        _setQuarantine(manifest.markets[0], 11);
        _setQuarantine(manifest.markets[1], 19);
        _approveCurrentResiduals();
        manifest.maxLostAssets = 29;
        _expectPreparationRevert("Batch C: loss exceeds limit");
        manifest.maxLostAssets = 30;
        manifest.maxQuarantinedAssets = 29;
        _expectPreparationRevert("Batch C: quarantine exceeds limit");
        manifest.maxQuarantinedAssets = 30;
        uint256 snapshot = vm.snapshotState();
        _executeStage();
        assertEq(vault.lostAssets(), 30);
        assertEq(vault.quarantinedAssets(manifest.markets[0]) + vault.quarantinedAssets(manifest.markets[1]), 30);
        _assertIntegrations(true);
        assertTrue(vm.revertToState(snapshot));
        _setAccounting(30, 30);
        _approveCurrentResiduals();
        manifest.maxLostAssets = 29;
        _expectPreparationRevert("Batch C: loss exceeds limit");
    }

    /// @dev Uses a controlled post-settlement snapshot with no shares/positions and explicitly approved nonzero accounting residue.
    /// Executes staged integration removal without erasing loss/quarantine; settlement and evidence validation remain external.
    function testBatchCExceptionalZeroPositionsAllowsOnlyApprovedAccountingAndQuarantineResidue() public {
        _startRecovery(true);
        // Controlled historical post-settlement snapshot. Settlement itself is external to the Vault ERP.
        _setAccounting(10, 10);
        _setQuarantine(manifest.markets[0], 7);
        _approveCurrentResiduals();
        _executeStage();
        _assertIntegrations(true);
        assertEq(vault.lostAssets(), 10);
        assertEq(vault.lastTotalAssets(), 10);
        assertEq(shares.totalAssets(), 10);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 7);
        _finishGuardianDelay();
        _generate();
        _assertOutcome("integration-removal-prepared");
        _executeOwner();
        _assertIntegrations(false);
        assertEq(vault.lostAssets(), 10);
        assertEq(vault.quarantinedAssets(manifest.markets[0]), 7);
        assertEq(Ownable(manifest.vault).owner(), address(timelock));
        _advanceSourceBlock();
        _generate();
        _assertOutcome("no-cleanup-required");
        _assertNoCalldata();
    }

    /// @dev Uses exceptional zero-claim cleanup, then changes residue or removes treatment evidence before final preparation.
    /// Rejects stale approvals or missing evidence and keeps both integrations available.
    function testBatchCFinalIntegrationPreparationRevalidatesExactResidueAndTreatment() public {
        _startRecovery(true);
        _setAccounting(10, 10);
        _approveCurrentResiduals();
        _executeStage();
        _finishGuardianDelay();
        _setAccounting(11, 11);
        _expectPreparationRevert("Batch C: accounting differs from approval");
        _approveCurrentResiduals();
        manifest.closureTreatmentReference = "";
        _expectPreparationRevert("Batch C: closure treatment reference missing");
        _assertIntegrations(true);
    }

    // Guardian removal has a native delay in addition to both governance transactions.

    /// @dev Varies ordinary closure with a conflicting replacement, pending zero guardian or already-accepted guardian removal.
    /// Executes both stages; conflicts restart the native delay, existing removal readiness is preserved and final roles clear.
    function testBatchCGuardianStatesPreserveNativeReadinessAndStagedRemoval() public {
        _startRecovery(true);
        // Cases: conflicting replacement, mature removal, removal already accepted.
        for (uint256 state; state < 3; ++state) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += state;
            vm.prank(address(timelock));
            vault.submitGuardian(state == 0 ? makeAddr("conflicting guardian") : address(0));
            uint256 originalReadyAt = vault.pendingGuardian().validAt;
            vm.warp(originalReadyAt);
            if (state == 2) vault.acceptGuardian(); // Already accepted by a permissionless caller.
            _executeStage();
            _assertIntegrations(true);
            if (state == 0) {
                assertEq(vault.guardian(), guardian);
                assertEq(vault.pendingGuardian().value, address(0));
                assertEq(vault.pendingGuardian().validAt, block.timestamp + vault.timelock());
                _expectPreparationRevert("Batch C: guardian removal not ready");
                _finishGuardianDelay();
            } else if (state == 1) {
                assertEq(vault.guardian(), guardian);
                assertEq(vault.pendingGuardian().validAt, originalReadyAt);
            } else {
                assertEq(vault.guardian(), address(0));
            }
            _generate();
            _executeOwner();
            assertEq(vault.guardian(), address(0));
            assertEq(vault.pendingGuardian().validAt, 0);
            _assertIntegrations(false);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses ordinary closure after guardian removal, with adapter, registry or both already removed externally.
    /// Executes remaining cleanup/integration work only; both absent yields a no-op with no remaining integrations.
    function testBatchCAlreadyRemovedIntegrationsAreSkippedOnRerun() public {
        _startRecovery(true);
        vm.prank(address(timelock));
        vault.submitGuardian(address(0));
        vm.warp(vault.pendingGuardian().validAt);
        vault.acceptGuardian();
        // Cases: adapter absent, registry absent, both absent.
        for (uint256 absent; absent < 3; ++absent) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += absent;
            if (absent != 1) _removeAdapterFixture();
            if (absent != 0) _removeRegistryFixture();
            _executeStage();
            _generate();
            if (absent == 2) {
                _assertNoCalldata();
                _assertOutcome("no-cleanup-required");
            } else {
                _executeOwner();
            }
            _assertIntegrations(false);
            assertEq(vault.guardian(), address(0));
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses final ordinary closure with controlled owner mismatches on still-registered integrations, then absent integrations.
    /// Rejects required unauthorized removals; once integrations are absent, generated guardian cleanup can still execute.
    function testBatchCFinalIntegrationOwnershipCheckedOnlyWhenRemovalNeeded() public {
        _startRecovery(true);
        _executeStage();
        _finishGuardianDelay();
        address adapterOwner = Ownable(address(adapter)).owner();
        address registryOwner = Ownable(contracts.vaultRegistry).owner();
        vm.mockCall(address(adapter), abi.encodeCall(Ownable.owner, ()), abi.encode(makeAddr("other owner")));
        _expectPreparationRevert("Batch C: adapter owner mismatch");
        vm.clearMockedCalls();
        vm.mockCall(contracts.vaultRegistry, abi.encodeCall(Ownable.owner, ()), abi.encode(makeAddr("other owner")));
        _expectPreparationRevert("Batch C: registry owner mismatch");
        vm.clearMockedCalls();
        assertEq(adapterOwner, address(timelock));
        assertEq(registryOwner, address(timelock));
        _removeAdapterFixture();
        _removeRegistryFixture();
        vm.mockCall(address(adapter), abi.encodeCall(Ownable.owner, ()), abi.encode(makeAddr("other owner")));
        vm.mockCall(contracts.vaultRegistry, abi.encodeCall(Ownable.owner, ()), abi.encode(makeAddr("other owner")));
        _generate();
        vm.clearMockedCalls();
        _executeOwner();
        assertEq(vault.guardian(), address(0));
        _assertIntegrations(false);
    }

    /// @dev Uses ordinary cleanup with a controlled Vault-owner mismatch or an unconfigured Timelock Safe.
    /// Rejects governance preparation without altering cleanup state or leaving executable files.
    function testBatchCCleanupRequiresVaultOwnerAndConfiguredTimelockSafe() public {
        _startRecovery(true);
        vm.mockCall(manifest.vault, abi.encodeCall(Ownable.owner, ()), abi.encode(makeAddr("other owner")));
        _expectPreparationRevert("ERP: Vault owner mismatch");
        vm.clearMockedCalls();
        manifest.timelockSafe = makeAddr("not a Safe");
        _expectPreparationRevert("ERP: missing Timelock Safe");
    }

    /// @dev Adds a newly approved token balance after initial ordinary cleanup and guardian readiness.
    /// Executes another token cleanup first; integrations remain until a fresh subsequent run removes them.
    function testBatchCAdditionalTokenCleanupDelaysIntegrationRemovalAgain() public {
        _startRecovery(true);
        _executeStage();
        _finishGuardianDelay();
        deal(address(asset), manifest.vault, 1 ether);
        manifest.tokens[0] = VaultOffboardingToken(1 ether, makeAddr("approved recipient"), address(asset));
        _generate();
        _assertOutcome("full-cleanup-prepared");
        _executeOwner();
        _assertIntegrations(true);
        _advanceSourceBlock();
        _generate();
        _assertOutcome("integration-removal-prepared");
        _executeOwner();
        _assertIntegrations(false);
    }

    /// @dev Adds a new market position after ordinary cleanup, then supplies exact exceptional residual approval.
    /// Rejects ordinary finalization; partial cleanup cancels pending guardian removal and preserves both integrations.
    function testBatchCNewPositionAfterCleanupPreventsFinalRemovalPreparation() public {
        _startRecovery(true);
        _executeStage();
        _finishGuardianDelay();
        _supplyOnBehalf(manifest.markets[0], 1 ether, manifest.vault);
        _expectPreparationRevert("Batch C: market claims remain");
        _approveCurrentResiduals();
        _generate();
        // Newly observed claims cancel even a matured pending guardian removal.
        _assertOutcome("partial-cleanup-prepared");
        _executeOwner();
        assertEq(vault.guardian(), guardian);
        _advanceSourceBlock();
        _generate();
        _assertNoCalldata();
        _assertOutcome("residual-claims");
        _assertIntegrations(true);
    }

    /// @dev Uses final ordinary removal with a controlled failure of the registry's removeVault call.
    /// Real Timelock execution rolls back guardian/adapter changes; removing the failure permits the same operation to finish.
    function testBatchCFinalIntegrationFailureRollsBackGuardianAcceptanceAndAdapterRemoval() public {
        _startRecovery(true);
        _executeStage();
        _finishGuardianDelay();
        _generate();
        bytes32 id = _scheduleOwner();
        vm.mockCallRevert(
            contracts.vaultRegistry,
            abi.encodeCall(IVaultRegistry.removeVault, (manifest.vault)),
            abi.encodeWithSignature("Error(string)", "registry temporarily unavailable")
        );
        _assertExecutionFails();
        assertEq(vault.guardian(), guardian);
        assertGt(vault.pendingGuardian().validAt, 0);
        _assertIntegrations(true);
        assertTrue(timelock.isOperationReady(id));
        vm.clearMockedCalls();
        _executeSafeFile(EXECUTE_FILE, manifest.timelockSafe);
        assertTrue(timelock.isOperationDone(id));
        _assertIntegrations(false);
    }

    // Reports are source snapshots and preparation outcomes, not execution receipts or permanent closure claims.

    /// @dev Uses stale cleanup artifacts, then introduces a market claim or malformed token inventory.
    /// Failed preparation removes selected outcome/calldata, preserving other phases and monitoring directories.
    function testBatchCFailedPreparationClearsOldOutcomeAndSelectedCalldataOnly() public {
        _startRecovery(true);
        _generate();
        string memory otherPhase = string.concat(_testRoot(), "/phase-1/sentinel.json");
        string memory monitor = string.concat(_testRoot(), "/monitor/sentinel.json");
        vm.createDir(string.concat(_testRoot(), "/phase-1"), true);
        vm.createDir(string.concat(_testRoot(), "/monitor"), true);
        vm.writeFile(otherPhase, "{}");
        vm.writeFile(monitor, "{}");
        _seedStaleArtifacts();
        _supplyOnBehalf(manifest.markets[0], 1 ether, manifest.vault);
        _expectPreparationRevert("Batch C: unresolved accounting");
        assertFalse(vm.keyExistsJson(vm.readFile(_path("exposure-report.json")), ".closure"));
        assertFalse(vm.exists(_path("closure-report.json")));
        assertEq(vm.readFile(otherPhase), "{}");
        assertEq(vm.readFile(monitor), "{}");
        _writeManifest();
        vm.writeJson("[]", manifestPath, ".tokens");
        _expectScriptRevert("ERP manifest: underlying token omitted");
        assertFalse(vm.exists(_path("exposure-report.json")));
        _assertNoCalldata();
    }

    /// @dev Uses exceptional residual claims after permitted partial cleanup, with stale governance files.
    /// Regeneration reports residual claims without transactions; monitoring leaves that prepared outcome unchanged.
    function testBatchCNoOpClearsStaleCalldataAndMonitoringDoesNotChangePreparedOutcome() public {
        _startRecovery(false);
        _approveCurrentResiduals();
        _executeStage();
        _approveCurrentResiduals();
        _generate();
        _assertOutcome("residual-claims");
        vm.writeFile(_path(SCHEDULE_FILE), "{}");
        vm.writeFile(_path(EXECUTE_FILE), "{}");
        _generate();
        _assertNoCalldata();
        string memory snapshot = vm.readFile(_path("exposure-report.json"));
        script.monitor(manifestPath, false);
        assertEq(vm.readFile(_path("exposure-report.json")), snapshot);
        _assertOutcome("residual-claims");
    }

    /// @dev Uses exact exceptional approvals but advances the fork without refreshing inputs, then corrupts closureMarkets.
    /// Rejects stale or malformed preparation and leaves no executable cleanup artifacts.
    function testBatchCRejectsStaleSourceBlockAndMalformedClosureApprovals() public {
        _startRecovery(false);
        _approveCurrentResiduals();
        _writeManifest();
        vm.roll(block.number + 1);
        _expectScriptRevert("ERP: fork block does not match manifest");
        _assertNoCalldata();
        manifest.sourceBlock = block.number;
        _writeManifest();
        vm.writeJson("[{}]", manifestPath, ".closureMarkets");
        _expectScriptRevert("");
        _assertNoCalldata();
    }

    // Helpers seed prior incident state; only generated artifacts execute the response being tested.

    function _startRecovery(bool redeem) private {
        _useFixture();
        _completeBatchA();
        phase = Phase.BATCH_C_RECOVER;
        manifest.tokens.push(VaultOffboardingToken(0, address(0), address(asset)));
        if (redeem) _redeemAll();
    }

    function _redeemAll() private {
        uint256 balance = shares.balanceOf(alice);
        vm.prank(alice);
        shares.redeem(balance, alice, alice);
        assertEq(shares.totalSupply(), 0);
        _advanceSourceBlock();
    }

    function _seedTokens(address firstRecipient, address secondRecipient) private {
        deal(address(asset), manifest.vault, 7 ether);
        manifest.tokens[0] = VaultOffboardingToken(7 ether, firstRecipient, address(asset));
        address other = IMarket(manifest.markets[0]).collateralToken();
        assertNotEq(other, address(asset));
        deal(other, manifest.vault, 11);
        manifest.tokens.push(VaultOffboardingToken(11, secondRecipient, other));
    }

    function _seedAdministrativeChanges() private {
        vm.prank(address(timelock));
        vault.submitTimelock(1 days);
        for (uint256 i; i < manifest.markets.length; ++i) {
            vm.prank(manifest.curatorSafe);
            vault.submitMarketRemoval(manifest.markets[i]);
        }
    }

    function _seedHistoricalQuarantine() private {
        // Prior exceptional removal fixture, using the real native delay and accounting transition.
        vm.prank(manifest.curatorSafe);
        vault.submitMarketRemoval(manifest.markets[0]);
        vm.warp(vault.config(manifest.markets[0]).removableAt);
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 1;
        indexes[1] = 2;
        vm.prank(manifest.curatorSafe);
        vault.updateWithdrawQueue(indexes);
        manifest.quarantinedMarkets.push(manifest.markets[0]);
        _advanceSourceBlock();
    }

    function _setAccounting(uint256 last, uint256 loss) private {
        // Controlled historical accounting residues; never overwrite state as part of response execution.
        stdstore.target(manifest.vault).sig("lastTotalAssets()").checked_write(last);
        stdstore.target(manifest.vault).sig("lostAssets()").checked_write(loss);
    }

    function _setQuarantine(address market, uint256 amount) private {
        stdstore.target(manifest.vault).sig("quarantinedAssets(address)").with_key(market).checked_write(amount);
    }

    function _approveCurrentResiduals() private {
        manifest.exceptionalClosure = true;
        manifest.closureApprovalReference = "governance/exact-residual-approval";
        manifest.closureTreatmentReference = "evidence/token-fee-reconciliation-and-claim-treatment";
        manifest.approvedTotalSupply = shares.totalSupply();
        manifest.approvedTotalAssets = shares.totalAssets();
        manifest.approvedLastTotalAssets = vault.lastTotalAssets();
        manifest.approvedLostAssets = vault.lostAssets();
        uint256 realAssets;
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            realAssets += vault.withdrawQueue(i).expectedSupplyAssets(manifest.vault);
        }
        manifest.maxLostAssets = manifest.approvedTotalAssets - realAssets;
        manifest.maxQuarantinedAssets = 0;
        delete manifest.closureMarkets;
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            uint256 quarantine = vault.quarantinedAssets(market);
            manifest.closureMarkets
                .push(
                    VaultOffboardingClosureMarket(
                        market.expectedSupplyAssets(manifest.vault),
                        quarantine,
                        IMarket(market).position(manifest.vault).supplyShares,
                        market
                    )
                );
            manifest.maxQuarantinedAssets += quarantine;
        }
    }

    function _finishGuardianDelay() private {
        assertEq(vault.pendingGuardian().value, address(0));
        uint256 readyAt = vault.pendingGuardian().validAt;
        assertGt(readyAt, 0);
        if (block.timestamp < readyAt) vm.warp(readyAt);
        _advanceSourceBlock();
    }

    function _assertOutcome(string memory expected) private view {
        string memory json = vm.readFile(_path("exposure-report.json"));
        assertEq(vm.parseJsonString(json, ".closure.outcome"), expected);
        assertEq(vm.parseJsonBool(json, ".closure.exceptionalClosure"), manifest.exceptionalClosure);
        assertEq(vm.parseJsonString(json, ".closure.closureApprovalReference"), manifest.closureApprovalReference);
        assertEq(vm.parseJsonString(json, ".closure.closureTreatmentReference"), manifest.closureTreatmentReference);
        _assertReportSnapshot();
        assertFalse(vm.exists(_path("closure-report.json")));
    }

    function _assertOrdinaryZeroState() private view {
        _assertClosedAllocation();
        assertEq(shares.totalSupply(), 0);
        assertEq(shares.totalAssets(), 0);
        assertEq(vault.lastTotalAssets(), 0);
        assertEq(vault.lostAssets(), 0);
        assertEq(vault.withdrawQueueLength(), 0);
        for (uint256 i; i < manifest.markets.length; ++i) {
            assertFalse(vault.config(manifest.markets[i]).enabled);
            assertEq(vault.config(manifest.markets[i]).removableAt, 0);
            assertEq(IMarket(manifest.markets[i]).position(manifest.vault).supplyShares, 0);
            assertEq(vault.quarantinedAssets(manifest.markets[i]), 0);
        }
    }

    function _assertRecoveryRoutes() private view {
        _assertIntegrations(true);
        assertEq(vault.curator(), manifest.curatorSafe);
        assertEq(vault.guardian(), guardian);
        assertEq(Ownable(manifest.vault).owner(), address(timelock));
    }

    function _assertExecutionFails() private {
        (address target, bytes memory data) = _transaction(vm.readFile(_path(EXECUTE_FILE)), 0);
        vm.prank(manifest.timelockSafe);
        (bool ok,) = target.call(data);
        assertFalse(ok, "unexpected successful governance execution");
    }

    function _removeAdapterFixture() private {
        vm.prank(Ownable(address(adapter)).owner());
        adapter.revokeContract(manifest.vault);
    }

    function _removeRegistryFixture() private {
        vm.prank(Ownable(contracts.vaultRegistry).owner());
        IVaultRegistry(contracts.vaultRegistry).removeVault(manifest.vault);
    }
}
