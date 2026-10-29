// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultOffboardingTestBase} from "./VaultOffboardingTestBase.sol";
import {VaultOffboardingSeverity} from "../IVaultOffboarding.sol";
import {IAltoVaultErrors, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {ERPVaultQueue} from "../../libraries/ERPVaultQueue.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IBundler3, Call} from "@morpho-org/bundler3/interfaces/IBundler3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BatchAContainTest is VaultOffboardingTestBase {
    using AltoBalancesLib for address;

    function setUp() public {
        _setUpFork();
    }

    /// @dev Uses the example manifest and pinned live deployment, with existing positions and integrations.
    /// Executes every generated Batch A stage; allocation closes while claims, curator, guardian and exit routes remain.
    function testBatchAExecutesPinnedLiveVaultArtifacts() public {
        _assertIntegrations(true);
        bytes32 claimsBefore = _claimsHash();
        address curatorBefore = vault.curator();
        address guardianBefore = vault.guardian();
        _completeBatchA();
        assertEq(_claimsHash(), claimsBefore);
        assertEq(vault.curator(), curatorBefore);
        assertEq(vault.guardian(), guardianBefore);
        _assertIntegrations(true);
    }

    /// @dev Uses funded fixture markets, mixed pending changes, a nonzero fee and one listed allocator.
    /// Executes containment, fee shutdown and role cleanup separately; rerunning the contained state is a no-op.
    function testBatchACompleteContainmentFromMixedCurrentState() public {
        _useFixture();
        _seedPendingChanges();
        bytes32 claimsBefore = _claimsHash();
        bytes32 controlsBefore = _preservedControlsHash();
        _generate();
        _executeSafeFile(CURATOR_FILE, manifest.curatorSafe);
        _executeOwner();
        _assertContained();
        assertEq(vault.fee(), 0.1 ether, "fee changed during containment");
        assertTrue(vault.isAllocator(revokedAllocator));
        _advanceSourceBlock();
        _generate();
        assertFalse(vm.exists(_path(CURATOR_FILE)));
        _executeOwner();
        assertEq(vault.fee(), 0);
        assertTrue(vault.isAllocator(revokedAllocator), "allocator revoked before fee stage completed");
        _advanceSourceBlock();
        _generate();
        _executeOwner();
        assertFalse(vault.isAllocator(revokedAllocator));
        assertTrue(vault.isAllocator(retainedAllocator));
        assertEq(_claimsHash(), claimsBefore);
        assertEq(_preservedControlsHash(), controlsBefore);
        _advanceSourceBlock();
        _generate();
        _assertNoCalldata();
    }

    /// @dev Uses a containment manifest whose pending caps, removals, guardian and timelock changes have matured.
    /// Executes revocations; existing administration remains and funded removal again fails its native check.
    function testBatchARevokesMaturedChangesWithoutAcceptingThem() public {
        _useFixture();
        _seedPendingChanges();
        vm.warp(block.timestamp + vault.timelock());
        uint256 delayBefore = vault.timelock();
        _executeStage();
        _assertContained();
        assertEq(vault.guardian(), guardian);
        assertEq(vault.timelock(), delayBefore);
        vm.expectRevert(IAltoVaultErrors.NoPendingValue.selector);
        vault.acceptCap(manifest.markets[0]);
        vm.expectRevert(IAltoVaultErrors.NoPendingValue.selector);
        vault.acceptGuardian();
        vm.expectRevert(IAltoVaultErrors.NoPendingValue.selector);
        vault.acceptTimelock();
        // Revocation restores the native rejection of removing this funded market.
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 2;
        vm.prank(manifest.curatorSafe);
        vm.expectRevert(
            abi.encodeWithSelector(IAltoVaultErrors.InvalidMarketRemovalNonZeroSupply.selector, manifest.markets[1])
        );
        vault.updateWithdrawQueue(indexes);
    }

    /// @dev Includes an enabled market with zero current cap but a pending increase in the reviewed inventory.
    /// Executes containment; the increase is revoked without disabling the market or removing its queue entry.
    function testBatchARevokesPendingIncreaseOnZeroCapMarket() public {
        _useFixture();
        vm.startPrank(manifest.curatorSafe);
        vault.submitCap(manifest.markets[2], 0);
        vault.submitCap(manifest.markets[2], 100 ether);
        vm.stopPrank();
        _executeStage();
        _assertContained();
        assertTrue(vault.config(manifest.markets[2]).enabled);
    }

    /// @dev Starts with mixed pending changes and separately finishes the curator, owner, or first curator transaction.
    /// Reruns generated files from each partial state; containment completes before fees change or allocators are revoked.
    function testBatchAPartialExecutionRerunsFinishContainmentBeforeFeeShutdown() public {
        _useFixture();
        _seedPendingChanges();
        for (uint256 completed; completed < 3; ++completed) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += completed;
            _generate();
            if (completed == 0) {
                // Curator finished; owner revocations remain.
                _executeSafeFile(CURATOR_FILE, manifest.curatorSafe);
            } else if (completed == 1) {
                // Owner finished; curator containment remains.
                _executeOwner();
            } else {
                // Only the first curator transaction was executed.
                (address target, bytes memory data) = _transaction(vm.readFile(_path(CURATOR_FILE)), 0);
                vm.prank(manifest.curatorSafe);
                (bool ok,) = target.call(data);
                assertTrue(ok);
            }
            _advanceSourceBlock();
            _executeStage();
            _assertContained();
            assertEq(vault.fee(), 0.1 ether, "fee changed before containment rerun completed");
            assertTrue(vault.isAllocator(revokedAllocator));
            _executeStage();
            assertEq(vault.fee(), 0);
            assertTrue(vault.isAllocator(revokedAllocator));
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses an already-zero fee and an allocator list containing both active and inactive permissions.
    /// Executes containment and revocation; only the listed active permission is lost, while essential roles still work.
    function testBatchASkipsZeroFeeAndInactiveListedAllocators() public {
        _useFixture();
        vm.prank(address(timelock));
        vault.setFee(0);
        manifest.allocatorsToRevoke.push(makeAddr("inactive allocator"));
        _executeStage();
        _generate();
        _executeOwner();
        assertFalse(vault.isAllocator(revokedAllocator));
        assertTrue(vault.isAllocator(retainedAllocator));
        // Owner and curator retain inherent allocator authority without an explicit mapping entry.
        vm.prank(manifest.curatorSafe);
        vault.setSupplyQueue(new address[](0));
        vm.prank(address(timelock));
        vault.setSupplyQueue(new address[](0));
        vm.prank(guardian);
        vault.revokePendingTimelock();
        vm.prank(revokedAllocator);
        vm.expectRevert(IAltoVaultErrors.NotAllocatorRole.selector);
        vault.setSupplyQueue(new address[](0));
    }

    /// @dev Uses a funded fixture with real borrowing and 30 days of interest under the previous Vault fee.
    /// Executes isolated fee shutdown; fee shares match native rounding and accrued assets before the fee becomes zero.
    function testBatchAFeeShutdownAccruesRealInterestBeforeSettingZero() public {
        _useFixture();
        _borrow(manifest.markets[0], 300 ether);
        FixedRateIrm(IMarket(manifest.markets[0]).irm()).setBorrowRate(0.2 ether / uint256(365 days));
        vm.warp(block.timestamp + 30 days);
        _executeStage();
        _assertFeeExecution(true);
    }

    /// @dev Uses otherwise identical manifests with no gain or a one-unit supply donation below fee-share precision.
    /// Executes containment and fee shutdown; neither case mints fee shares and accounting remains correct.
    function testBatchAFeeShutdownMintsNoSharesForZeroOrRoundingInterest() public {
        _useFixture();
        for (uint256 donation; donation < 2; ++donation) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += donation;
            if (donation != 0) _supplyOnBehalf(manifest.markets[0], donation, manifest.vault);
            assertEq(shares.totalAssets() - vault.lastTotalAssets(), donation);
            _executeStage();
            _assertFeeExecution(false);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Includes a historical native quarantine, with its loss either already stored or awaiting accrual.
    /// Executes all containment stages; the residual position, quarantine and loss survive and appear in the snapshot.
    function testBatchAPreservesQuarantineWithStoredOrUnaccruedLoss() public {
        _useFixture();
        _quarantineFirstMarket();
        uint256 quarantine = vault.quarantinedAssets(manifest.markets[0]);
        assertGt(quarantine, 0);
        for (uint256 accrued; accrued < 2; ++accrued) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += accrued;
            if (accrued != 0) {
                vm.prank(address(timelock));
                vault.setFee(0.2 ether); // Native accounting accrual before activation.
            }
            assertEq(vault.lostAssets(), accrued == 0 ? 0 : quarantine);
            bytes32 claimsBefore = _claimsHash();
            _executeStage();
            _assertFeeExecution(false);
            _assertContained();
            assertEq(_claimsHash(), claimsBefore);
            assertEq(vault.lostAssets(), quarantine);
            assertEq(vault.quarantinedAssets(manifest.markets[0]), quarantine);
            assertFalse(vault.config(manifest.markets[0]).enabled);
            _advanceSourceBlock();
            _generate();
            assertEq(_reportAmount(".lostAssets"), quarantine);
            assertEq(_reportAmount(".markets[0].quarantinedAssets"), quarantine);
            assertEq(
                _reportAmount(".markets[0].supplyShares"),
                IMarket(manifest.markets[0]).position(manifest.vault).supplyShares
            );
            _executeOwner();
            assertFalse(vault.isAllocator(revokedAllocator));
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses a fully contained fixture and a funded entrant with an allowance to the Vault.
    /// Attempts positive deposit and mint; both revert without changing balances, allowances, shares or existing claims.
    function testBatchADepositAndMintRevertAtomically() public {
        _useFixture();
        _completeBatchA();
        address entrant = makeAddr("new depositor");
        deal(address(asset), entrant, 10 ether);
        vm.prank(entrant);
        asset.approve(manifest.vault, 10 ether);
        bytes32 beforeState = _entryStateHash(entrant);
        vm.prank(entrant);
        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        shares.deposit(1 ether, entrant);
        assertEq(_entryStateHash(entrant), beforeState);
        vm.prank(entrant);
        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        shares.mint(1 ether, entrant);
        assertEq(_entryStateHash(entrant), beforeState);
        _assertContained();
    }

    /// @dev Uses a contained Vault whose destination caps are all zero, while an essential allocator remains authorized.
    /// Attempts balanced reallocation and an idle recall; both revert without moving assets or changing positions.
    function testBatchABlocksPositiveReallocationAndIdleRecallAtomically() public {
        _useFixture();
        _completeBatchA();
        bytes32 claimsBefore = _claimsHash();
        uint256 idleBefore = asset.balanceOf(manifest.vault);
        MarketAllocation[] memory allocations = new MarketAllocation[](2);
        allocations[0] = MarketAllocation(manifest.markets[0], 500 ether);
        allocations[1] = MarketAllocation(manifest.markets[2], type(uint256).max);
        vm.prank(retainedAllocator);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.SupplyCapExceeded.selector, manifest.markets[2]));
        vault.reallocate(allocations);
        assertEq(_claimsHash(), claimsBefore);
        assertEq(asset.balanceOf(manifest.vault), idleBefore);
        allocations = new MarketAllocation[](1);
        allocations[0] = MarketAllocation(manifest.markets[0], 500 ether);
        vm.prank(retainedAllocator);
        vm.expectRevert(IAltoVaultErrors.InconsistentReallocation.selector);
        vault.reallocate(allocations);
        assertEq(_claimsHash(), claimsBefore);
        assertEq(asset.balanceOf(manifest.vault), idleBefore);
    }

    /// @dev Includes a market with one supply share whose expected assets round down to zero.
    /// Executes Batch A; the nonzero position remains enabled, queued and unchanged despite its zero asset estimate.
    function testBatchAPreservesNonzeroMarketSharesWhoseAssetsRoundToZero() public {
        _useFixture();
        address market = manifest.markets[2];
        deal(address(asset), address(this), 1);
        asset.approve(market, 1);
        IMarket(market).addSupply(0, 1, manifest.vault);
        assertEq(market.expectedSupplyAssets(manifest.vault), 0);
        assertEq(IMarket(market).position(manifest.vault).supplyShares, 1);
        bytes32 claimsBefore = _claimsHash();
        _completeBatchA();
        assertEq(_claimsHash(), claimsBefore);
        assertTrue(vault.config(market).enabled);
        assertEq(vault.withdrawQueue(2), market);
    }

    /// @dev Uses fully liquid funded markets and a standard containment manifest.
    /// Executes Batch A, then direct withdrawal and final redemption; shareholder and market shares reach zero.
    function testBatchAPreservesWithdrawRedeemAndFinalShareholderExit() public {
        _useFixture();
        _completeBatchA();
        assertEq(shares.maxWithdraw(alice), 1_000 ether);
        uint256 supplyBefore = shares.totalSupply();
        vm.startPrank(alice);
        uint256 burned = shares.withdraw(100 ether, alice, alice);
        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(shares.totalSupply(), supplyBefore - burned);
        uint256 redeemed = shares.redeem(shares.balanceOf(alice), alice, alice);
        vm.stopPrank();
        assertEq(asset.balanceOf(alice), 100 ether + redeemed);
        assertEq(shares.totalSupply(), 0);
        assertEq(asset.balanceOf(manifest.vault), 0);
        assertEq(IMarket(manifest.markets[0]).position(manifest.vault).supplyShares, 0);
        assertEq(IMarket(manifest.markets[1]).position(manifest.vault).supplyShares, 0);
    }

    /// @dev Uses a contained Vault that remains approved by the adapter.
    /// Executes adapter withdrawal and redemption; the shareholder receives the previewed assets and approval remains.
    function testBatchAPreservesAdapterWithdrawAndRedeemRoutes() public {
        _useFixture();
        _completeBatchA();
        _withdrawThroughAdapter(10 ether);
        assertEq(asset.balanceOf(alice), 10 ether);
        uint256 shareAmount = shares.maxRedeem(alice) / 2;
        uint256 expectedAssets = shares.previewRedeem(shareAmount);
        _redeemThroughAdapter(shareAmount);
        assertEq(asset.balanceOf(alice), 10 ether + expectedAssets);
        assertTrue(adapter.isApprovedContract(manifest.vault));
    }

    /// @dev Uses a contained Vault with a one-unit market donation that makes its share price non-integral.
    /// Redeems the final shareholder; rounding dust remains recorded in an enabled market and the next report.
    function testBatchAFinalShareholderRoundingLeavesExplicitMarketDust() public {
        _useFixture();
        _completeBatchA();
        // A one-unit supply donation makes the share price non-integral after containment.
        _supplyOnBehalf(manifest.markets[0], 1, manifest.vault);
        uint256 allShares = shares.balanceOf(alice);
        uint256 assetsBefore = shares.totalAssets();
        uint256 expectedAssets = allShares * (assetsBefore + 1) / (shares.totalSupply() + 1);
        assertLt(shares.maxRedeem(alice), allShares, "fixture must exercise conservative rounding");
        vm.prank(alice);
        uint256 received = shares.redeem(allShares, alice, alice);
        assertEq(received, expectedAssets);
        assertEq(asset.balanceOf(alice), received);
        assertEq(shares.totalSupply(), 0);
        assertEq(shares.totalAssets(), assetsBefore - received);
        assertEq(shares.totalAssets(), 1);
        assertGt(IMarket(manifest.markets[1]).position(manifest.vault).supplyShares, 0);
        _advanceSourceBlock();
        _generate();
        _assertNoCalldata();
        assertEq(_reportAmount(".markets[1].expectedSupplyAssets"), 1);
        assertTrue(vault.config(manifest.markets[1]).enabled, "rounding residue was discarded");
    }

    /// @dev Uses a contained Vault with adapter approval retained and underlying held by the adapter.
    /// Attempts adapter deposit and mint; both revert atomically while balances, allowances and approval remain intact.
    function testBatchAAdapterDepositAndMintRemainBlockedWithoutDisablingExits() public {
        _useFixture();
        _completeBatchA();
        IBundler3 bundler = IBundler3(adapter.BUNDLER3());
        // The adapter remains approved for exits, but entry calls still reach the Vault's closed supply path.
        deal(address(asset), address(adapter), 10 ether);
        uint256 supplyBefore = shares.totalSupply();
        uint256 allowanceBefore = asset.allowance(address(adapter), manifest.vault);
        Call[] memory calls = new Call[](1);
        calls[0] = Call(
            address(adapter),
            abi.encodeCall(AltoAdapter.erc4626Deposit, (manifest.vault, 1 ether, type(uint256).max, alice)),
            0,
            false,
            bytes32(0)
        );
        vm.prank(alice);
        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        bundler.multicall(calls);
        calls[0].data = abi.encodeCall(AltoAdapter.erc4626Mint, (manifest.vault, 1 ether, type(uint256).max, alice));
        vm.prank(alice);
        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        bundler.multicall(calls);
        assertEq(asset.balanceOf(address(adapter)), 10 ether);
        assertEq(asset.allowance(address(adapter), manifest.vault), allowanceBefore);
        assertEq(shares.totalSupply(), supplyBefore);
        assertTrue(adapter.isApprovedContract(manifest.vault));
    }

    /// @dev Uses either a controlled token shortage or real borrowing against the funded markets.
    /// Executes containment and the available withdrawal; reports match liquidity and further exits cannot erase claims.
    function testBatchALimitedLiquidityReportsAndPreservesUnwithdrawnClaims() public {
        _useFixture();
        for (uint256 borrowed; borrowed < 2; ++borrowed) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += borrowed;
            if (borrowed == 0) {
                // Actual token shortage with unchanged accounting supply.
                deal(address(asset), manifest.markets[0], 20 ether);
            } else {
                _borrow(manifest.markets[0], 600 ether);
                _borrow(manifest.markets[1], 300 ether);
            }
            _completeBatchA();
            uint256 available = borrowed == 0 ? 420 ether : 100 ether;
            assertEq(_reportAmount(".markets[0].marketAvailableLiquidity"), borrowed == 0 ? 20 ether : 0);
            assertEq(_reportAmount(".markets[0].estimatedAvailableLiquidity"), borrowed == 0 ? 20 ether : 0);
            assertEq(_reportAmount(".markets[0].expectedSupplyAssets"), 600 ether);
            assertEq(shares.maxWithdraw(alice), available);
            assertGt(shares.maxRedeem(alice), 0);
            vm.prank(alice);
            shares.withdraw(available, alice, alice);
            assertEq(asset.balanceOf(alice), available);
            assertEq(shares.maxWithdraw(alice), 0);
            assertEq(shares.maxRedeem(alice), 0);
            assertGt(shares.balanceOf(alice), 0);
            assertGt(IMarket(manifest.markets[0]).position(manifest.vault).supplyShares, 0);
            bytes32 beforeState = _entryStateHash(alice);
            vm.prank(alice);
            vm.expectRevert(IAltoVaultErrors.NotEnoughLiquidity.selector);
            shares.withdraw(1, alice, alice);
            assertEq(_entryStateHash(alice), beforeState);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses separate paused and frozen market fixtures under the same containment manifest.
    /// Executes Batch A and an available exit; native liquidity restrictions and market control settings are preserved.
    function testBatchAPausedAndFrozenMarketsPreserveAvailableExits() public {
        _useFixture();
        for (uint256 frozen; frozen < 2; ++frozen) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += frozen;
            bytes32 pauseType = frozen == 0 ? PAUSE_TYPE : FROZEN_TYPE;
            IMarket(manifest.markets[0]).pause(pauseType, true);
            _completeBatchA();
            assertTrue(IMarket(manifest.markets[0]).paused(pauseType));
            assertEq(shares.maxWithdraw(alice), frozen == 0 ? 400 ether : 1_000 ether);
            assertEq(_reportAmount(".markets[0].estimatedAvailableLiquidity"), frozen == 0 ? 0 : 600 ether);
            vm.prank(alice);
            shares.withdraw(100 ether, alice, alice);
            assertEq(asset.balanceOf(alice), 100 ether);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses a contained Vault receiving both a direct underlying donation and permissionless supply on its behalf.
    /// Reruns reporting; idle tokens and market assets are distinguished without reopening deposits or minting shares.
    function testBatchADirectInflowsRemainPossibleAndAreReportedSeparately() public {
        _useFixture();
        _completeBatchA();
        uint256 supplyBefore = shares.totalSupply();
        uint256 assetsBefore = shares.totalAssets();
        deal(address(asset), address(this), 7 ether);
        asset.transfer(manifest.vault, 7 ether);
        assertEq(shares.totalAssets(), assetsBefore, "idle donation counted as market assets");
        _supplyOnBehalf(manifest.markets[0], 11 ether, manifest.vault);
        assertEq(shares.totalSupply(), supplyBefore, "donation minted shareholder shares");
        assertEq(shares.totalAssets(), assetsBefore + 11 ether);
        _advanceSourceBlock();
        _generate();
        _assertNoCalldata();
        assertEq(_reportAmount(".directUnderlyingAssets"), 7 ether);
        assertEq(_reportAmount(".markets[0].expectedSupplyAssets"), 611 ether);
        _assertContained();
    }

    /// @dev Varies the curator Safe, Vault owner or Timelock Safe while using the same containment inventory.
    /// Rejects required unauthorized work; curator-only containment and owner-only fee shutdown use only relevant roles.
    function testBatchAAuthorizationIsRequiredOnlyForPendingRoleWork() public {
        _useFixture();
        for (uint256 role; role < 3; ++role) {
            uint256 snapshot = vm.snapshotState();
            manifest.step += role;
            if (role == 0) {
                address correct = manifest.curatorSafe;
                manifest.curatorSafe = makeAddr("wrong curator");
                _expectPreparationRevert("ERP: unauthorized curator Safe");
                manifest.curatorSafe = correct;
                _executeStage();
                manifest.curatorSafe = makeAddr("unused curator field");
                _executeStage();
                assertEq(vault.fee(), 0);
            } else {
                if (role == 1) {
                    address newOwner = makeAddr("different owner");
                    vm.prank(address(timelock));
                    Ownable(manifest.vault).transferOwnership(newOwner);
                    vm.prank(newOwner);
                    AltoVault(manifest.vault).acceptOwnership();
                } else {
                    manifest.timelockSafe = address(0);
                }
                _executeStage(); // Only curator work is required in this source state.
                _assertContained();
                assertEq(vault.fee(), 0.1 ether);
                _expectPreparationRevert(role == 1 ? "ERP: Vault owner mismatch" : "ERP: missing Timelock Safe");
            }
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses generated containment and governance files for a manifest with pending administrative changes.
    /// Unauthorized execution leaves claims unchanged; the recorded Safe and real Timelock then complete containment.
    function testBatchAGeneratedCallsRejectUnauthorizedSenders() public {
        _useFixture();
        _seedPendingChanges();
        _generate();
        bytes32 beforeState = _claimsHash();
        (address target, bytes memory data) = _transaction(vm.readFile(_path(CURATOR_FILE)), 0);
        vm.prank(makeAddr("unauthorized"));
        (bool ok,) = target.call(data);
        assertFalse(ok);
        (target, data) = _transaction(vm.readFile(_path(SCHEDULE_FILE)), 0);
        vm.prank(makeAddr("unauthorized"));
        (ok,) = target.call(data);
        assertFalse(ok);
        assertEq(_claimsHash(), beforeState);
        _executeSafeFile(CURATOR_FILE, manifest.curatorSafe);
        _executeOwner(); // Checks the real governance delay as well.
        _assertContained();
    }

    /// @dev Uses a positive-cap market with missing registration or a controlled incompatible underlying getter.
    /// Rejects invalid reductions; after the cap is zero, historical registration is unnecessary and funded claims remain.
    function testBatchACapReductionRequiresRegisteredMatchingAssetButAllowsZeroCapHistory() public {
        _useFixture();
        address market = manifest.markets[0];
        vm.prank(Ownable(address(registry)).owner());
        registry.removeBorrowMarket(market);
        _expectPreparationRevert("Batch A: cap reduction needs registered market");
        vm.prank(Ownable(address(registry)).owner());
        registry.addBorrowMarket(market);
        // The underlying is immutable; only this invalid-destination case controls its getter.
        address wrongToken = IMarket(market).collateralToken();
        vm.mockCall(market, abi.encodeWithSelector(IMarketBase.borrowToken.selector), abi.encode(wrongToken));
        _expectPreparationRevert("Batch A: inconsistent market asset");
        vm.clearMockedCalls();
        vm.prank(manifest.curatorSafe);
        vault.submitCap(market, 0);
        vm.prank(Ownable(address(registry)).owner());
        registry.removeBorrowMarket(market);
        _completeBatchA();
        assertTrue(vault.config(market).enabled);
        assertEq(_reportAmount(".markets[0].supplyShares"), IMarket(market).position(manifest.vault).supplyShares);
    }

    /// @dev Removes a current market from the manifest, first while supplied and then while only in the withdrawal queue.
    /// Rejects both incomplete inventories; restoring the reviewed market allows generated containment to execute.
    function testBatchARejectsOmittedSupplyAndWithdrawalMarkets() public {
        _useFixture();
        address[] memory complete = manifest.markets;
        manifest.markets.pop();
        _expectPreparationRevert("ERP: supply market omitted");
        vm.prank(manifest.curatorSafe);
        vault.setSupplyQueue(new address[](0));
        _expectPreparationRevert("ERP: withdrawal market omitted");
        manifest.markets = complete;
        _executeStage();
        _assertContained();
    }

    /// @dev Corrupts reviewed markets, quarantine history or the explicit allocator list with duplicates or invalid entries.
    /// Rejects each manifest without changing the bound Vault or leaving executable artifacts.
    function testBatchARejectsDuplicateZeroAndInconsistentInventories() public {
        _useFixture();
        address first = manifest.markets[0];
        manifest.markets[0] = manifest.markets[1];
        _expectPreparationRevert("ERP manifest: duplicate address");
        manifest.markets[0] = address(0);
        _expectPreparationRevert("ERP manifest: zero address");
        manifest.markets[0] = first;
        manifest.quarantinedMarkets = _oneAddress(makeAddr("outside reviewed inventory"));
        _expectPreparationRevert("ERP manifest: quarantine market omitted");
        delete manifest.quarantinedMarkets;
        manifest.allocatorsToRevoke.push(revokedAllocator);
        _expectPreparationRevert("ERP manifest: duplicate address");
    }

    /// @dev Omits required allocator/curator inputs or selects a source block different from the fork.
    /// Rejects malformed or stale preparation; the Vault remains unchanged and no executable plan survives.
    function testBatchARejectsMissingRequiredInputsAndWrongSourceBlock() public {
        _useFixture();
        _writeManifest();
        string memory json = vm.readFile(manifestPath);
        vm.writeFile(manifestPath, vm.replace(json, '"allocatorsToRevoke"', '"unusedAllocators"'));
        _expectScriptRevert("ERP manifest: missing allocator list");
        vm.writeFile(manifestPath, vm.replace(json, '"curatorSafe"', '"unusedCurator"'));
        _expectScriptRevert("");
        manifest.sourceBlock++;
        _expectPreparationRevert("ERP: fork block does not match manifest");
    }

    /// @dev Uses each severity with a future T0 and no Batch B notice or action inputs.
    /// Executes generated containment for every severity; allocation closes immediately without a notice gate.
    function testBatchAAllSeveritiesUseSameControlsWithoutNoticeOrT0Gate() public {
        _useFixture();
        manifest.t0 = block.timestamp + 365 days;
        for (uint256 i; i < 3; ++i) {
            uint256 snapshot = vm.snapshotState();
            manifest.severity = VaultOffboardingSeverity(i);
            manifest.step += i;
            _generate(); // Minimal test manifest contains no notice, action, recovery or borrower inputs.
            _executeSafeFile(CURATOR_FILE, manifest.curatorSafe);
            _assertContained();
            assertTrue(vm.revertToState(snapshot));
        }
    }

    /// @dev Uses funded markets, pending changes and supplied shareholders; one market names the Vault as fee recipient.
    /// Checks copied inputs and source observations, then executes containment without changing the saved snapshot.
    /// The reported market fee recipient still requires external operator review; preparation does not certify it.
    function testBatchAReportsSourceStateAndCopiesExactInput() public {
        _useFixture();
        _seedPendingChanges();
        IMarket(manifest.markets[0]).setFeeRecipient(manifest.vault);
        _generate();
        string memory report = vm.readFile(_path("exposure-report.json"));
        _assertReportSnapshot();
        assertEq(vm.parseJsonAddress(report, ".markets[0].feeRecipient"), manifest.vault);
        assertEq(vm.parseJsonAddress(report, ".vault"), manifest.vault);
        assertEq(_reportAmount(".fee"), vault.fee());
        assertEq(_reportAmount(".shareholders[0].shares"), shares.balanceOf(alice));
        assertEq(_reportAmount(".shareholders[0].maxWithdraw"), shares.maxWithdraw(alice));
        assertEq(_reportAmount(".shareholders[0].maxRedeem"), shares.maxRedeem(alice));
        assertEq(vm.parseJsonUint(report, ".pendingGuardianAt"), vault.pendingGuardian().validAt);
        assertEq(vm.parseJsonUint(report, ".pendingTimelockAt"), vault.pendingTimelock().validAt);
        assertEq(vm.parseJsonAddressArray(report, ".withdrawQueue"), ERPVaultQueue.withdrawQueue(vault));
        assertEq(vm.parseJsonAddressArray(report, ".quarantinedMarkets"), manifest.quarantinedMarkets);
        assertEq(vm.readFile(_path("inputs.json")), vm.readFile(manifestPath));
        assertFalse(vm.keyExistsJson(report, ".closure"));
        assertFalse(vm.exists(_path("borrowers.json")));
        _executeSafeFile(CURATOR_FILE, manifest.curatorSafe);
        _executeOwner();
        _assertContained();
        assertEq(vm.readFile(_path("exposure-report.json")), report, "snapshot changed during execution");
    }

    /// @dev Uses an unauthorized curator, a contained no-op and missing inputs, with stale reports and directory sentinels.
    /// Preparation failure keeps a fresh snapshot; no-op/parsing failure clear selected stale files and preserve other outputs.
    function testBatchANoOpAndFailureClearOnlySelectedArtifacts() public {
        _useFixture();
        _generate();
        vm.writeJson('{"outcome":"stale"}', _path("exposure-report.json"), ".closure");
        address curator = manifest.curatorSafe;
        manifest.curatorSafe = makeAddr("wrong curator");
        _expectPreparationRevert("ERP: unauthorized curator Safe");
        assertFalse(vm.keyExistsJson(vm.readFile(_path("exposure-report.json")), ".closure"));
        _assertReportSnapshot();
        manifest.curatorSafe = curator;
        _completeBatchA();
        string memory other = string.concat(_testRoot(), "/phase-1/step-1/source-block-1/action-0");
        string memory monitoring = string.concat(_testRoot(), "/monitor/step-1/source-block-1");
        vm.createDir(other, true);
        vm.createDir(monitoring, true);
        vm.writeFile(string.concat(other, "/vault-curator-safe.json"), "keep other phase");
        vm.writeFile(string.concat(monitoring, "/exposure-report.json"), "keep monitoring");
        string[6] memory names = _seedStaleArtifacts();
        _generate();
        _assertNoCalldata();
        assertFalse(vm.exists(_path("closure-report.json")));
        assertFalse(vm.keyExistsJson(vm.readFile(_path("exposure-report.json")), ".closure"));
        _seedStaleArtifacts();
        _writeManifest();
        vm.writeFile(manifestPath, vm.replace(vm.readFile(manifestPath), '"allocatorsToRevoke"', '"unusedAllocators"'));
        _expectScriptRevert("ERP manifest: missing allocator list");
        for (uint256 i; i < names.length; ++i) {
            assertFalse(vm.exists(_path(names[i])));
        }
        assertEq(vm.readFile(string.concat(other, "/vault-curator-safe.json")), "keep other phase");
        assertEq(vm.readFile(string.concat(monitoring, "/exposure-report.json")), "keep monitoring");
    }

    /// @dev Creates the same pending guardian replacement in two distinct source-block/run directories.
    /// Executes both generated Timelock operations successfully; both complete and the first run's artifact survives.
    function testBatchASeparateRunsExecuteRepeatedGovernanceRevocations() public {
        _useFixture();
        bytes32 firstId;
        string memory firstPath;
        string memory firstJson;
        for (uint256 run; run < 2; ++run) {
            vm.prank(address(timelock));
            vault.submitGuardian(makeAddr("pending replacement"));
            _advanceSourceBlock();
            manifest.step += run;
            _generate();
            bytes32 id = _executeOwner();
            assertEq(vault.pendingGuardian().validAt, 0);
            assertEq(vault.guardian(), guardian);
            if (run == 0) {
                firstId = id;
                firstPath = _path(EXECUTE_FILE);
                firstJson = vm.readFile(firstPath);
            } else {
                assertTrue(timelock.isOperationDone(firstId));
                assertTrue(timelock.isOperationDone(id));
                assertEq(vm.readFile(firstPath), firstJson);
            }
        }
    }

    /// @dev Independent ERC-4626 fee-share expectation at the actual execution timestamp, including virtual shares/assets.
    function _assertFeeExecution(bool expectFeeShares) private {
        _generate();
        bytes32 id = _scheduleOwner();
        uint256 supplyBefore = shares.totalSupply();
        uint256 recipientBefore = shares.balanceOf(vault.feeRecipient());
        uint256 realAssets;
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            realAssets += vault.withdrawQueue(i).expectedSupplyAssets(manifest.vault);
        }
        uint256 loss = Math.max(
            vault.lostAssets(), vault.lastTotalAssets() > realAssets ? vault.lastTotalAssets() - realAssets : 0
        );
        uint256 expectedTotalAssets = realAssets + loss;
        uint256 feeAssets = (expectedTotalAssets - vault.lastTotalAssets()) * vault.fee() / 1 ether;
        uint256 expectedShares = feeAssets * (supplyBefore + 10 ** AltoVault(manifest.vault).DECIMALS_OFFSET())
            / (expectedTotalAssets - feeAssets + 1);
        if (expectFeeShares) assertGt(expectedShares, 0);
        else assertEq(expectedShares, 0);
        _executeSafeFile(EXECUTE_FILE, manifest.timelockSafe);
        assertTrue(timelock.isOperationDone(id));
        assertEq(vault.fee(), 0);
        assertEq(shares.balanceOf(vault.feeRecipient()) - recipientBefore, expectedShares);
        assertEq(shares.totalSupply() - supplyBefore, expectedShares);
        assertEq(vault.lastTotalAssets(), expectedTotalAssets);
        assertEq(vault.lostAssets(), loss);
    }

    /// @dev Establishes a pre-existing quarantined position through native calls; Batch A must only preserve/report it.
    function _quarantineFirstMarket() private {
        address market = manifest.markets[0];
        vm.startPrank(manifest.curatorSafe);
        vault.submitCap(market, 0);
        vault.submitMarketRemoval(market);
        vm.warp(vault.config(market).removableAt);
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 1;
        indexes[1] = 2;
        vault.updateWithdrawQueue(indexes);
        vault.setSupplyQueue(_oneAddress(manifest.markets[1]));
        vm.stopPrank();
        manifest.quarantinedMarkets = _oneAddress(market);
    }

    function _entryStateHash(address account) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                _claimsHash(),
                asset.balanceOf(account),
                asset.balanceOf(manifest.vault),
                asset.allowance(account, manifest.vault),
                shares.totalSupply(),
                shares.balanceOf(account),
                shares.balanceOf(vault.feeRecipient()),
                vault.lastTotalAssets(),
                vault.lostAssets()
            )
        );
    }

    function _preservedControlsHash() private view returns (bytes32 hash) {
        hash = keccak256(
            abi.encode(
                _marketControlsHash(),
                Ownable(manifest.vault).owner(),
                vault.curator(),
                vault.guardian(),
                vault.timelock(),
                vault.feeRecipient(),
                vault.skimRecipient(),
                adapter.isApprovedContract(manifest.vault),
                IVaultRegistry(contracts.vaultRegistry).isVault(manifest.vault)
            )
        );
    }
}
