// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingPhase, BorrowMarketOffboardingVault} from "../IBorrowMarketOffboarding.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IAltoVault, IAltoVaultErrors, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchCRecoverTest is BorrowMarketOffboardingTestBase {
    using AltoBalancesLib for address;

    struct RecoveryMarketSnapshot {
        address oracle;
        address irm;
        address liquidationEngine;
        address feeRecipient;
        uint256 maxLtv;
        uint256 borrowOpeningFee;
        uint256 borrowRate;
        bytes32 liquidationConfigurationHash;
        Balance totalSupply;
        address legacyUser;
        Position legacyPosition;
    }

    struct UnaffectedMarketSnapshot {
        address market;
        address leverage;
        address swapper;
        address irm;
        uint256 maxLtv;
        bytes32 liquidationConfigurationHash;
        Balance totalSupply;
        Balance totalBorrowed;
        uint128 vaultSupplyShares;
        bytes32 vaultConfigurationHash;
        bool frozen;
        bool paused;
        bool registered;
        bool adapterApproved;
        bool leverageSupported;
        bool callbackAuthorized;
        bool swapperWhitelisted;
        bool peripherySupported;
        bool peripheryAuthorized;
        bool inSupplyQueue;
        bool inWithdrawQueue;
    }

    RecoveryMarketSnapshot[] internal recoverySnapshots;
    UnaffectedMarketSnapshot[] private unaffectedMarkets;
    address[] private originalSupplyQueue;

    function setUp() public {
        _setUpManifest();
    }

    /// @dev Uses the configured markets without affected Vaults and mocks every market at zero debt. It then gives one
    /// market either one remaining borrow share or one remaining borrowed asset and verifies Batch C rejects both cases.
    /// Recovery is allowed only when both terminal debt targets are independently zero for every manifest market.
    function testBatchCRequiresBothZeroDebtTargets() public {
        manifest.activationId = "batch-c-debt-targets";
        delete manifest.vaults;
        _mockZeroDebt();

        vm.mockCall(
            borrowMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 1}))
        );
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market debt remains");

        _mockZeroDebt();
        vm.mockCall(
            borrowMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 1, shares: 0}))
        );
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market debt remains");
    }

    /// @dev Mutates the standard recovery manifest one field at a time: zero registry, adapter, liquidation periphery,
    /// leverage or Vault addresses; an unauthorized allocator; and duplicate Vault entries. Each malformed input must be
    /// rejected during preparation so no recovery transaction can be generated from an invalid manifest configuration.
    function testBatchCRejectsInvalidRecoveryConfiguration() public {
        manifest.activationId = "batch-c-invalid-configuration";

        address original = input.contracts.marketRegistry;
        input.contracts.marketRegistry = address(0);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: zero registry");
        input.contracts.marketRegistry = original;

        original = input.contracts.altoAdapter;
        input.contracts.altoAdapter = address(0);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: zero adapter");
        input.contracts.altoAdapter = original;

        original = input.contracts.liquidationPeriphery;
        input.contracts.liquidationPeriphery = address(0);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: zero liquidation periphery");
        input.contracts.liquidationPeriphery = original;

        original = manifest.markets[0].leverage;
        manifest.markets[0].leverage = address(0);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: zero leverage");
        manifest.markets[0].leverage = original;

        BorrowMarketOffboardingVault memory affectedVault = manifest.vaults[0];
        manifest.vaults[0].allocator = makeAddr("unauthorized-allocator");
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: unauthorized Vault allocator");
        manifest.vaults[0] = affectedVault;

        manifest.vaults[0].vault = address(0);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: zero Vault");

        delete manifest.vaults;
        _pushManifestVault(affectedVault);
        _pushManifestVault(affectedVault);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: duplicate Vault");
    }

    /// @dev Executes the prerequisite phases to zero market debt while the affected Vault still has market exposure, then
    /// verifies Batch C rejects remaining supply shares. After real reallocation, it separately tests quarantined assets,
    /// nonzero caps, pending cap/removal actions and supply-queue membership. Recovery proceeds only after the generated
    /// allocator plans remove the affected markets from both Vault queues and disable their Vault configurations.
    function testBatchCRejectsIncompleteVaultExitStates() public {
        manifest.activationId = "batch-c-vault-gates";
        _executePrerequisitePhases();

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: Vault market supply remains");

        address replacement = _approveRecoveryReplacementMarket(_affectedVaultSupplyAssets() + 1 ether);
        _reallocateVaultToReplacement(replacement);

        address market = borrowMarkets[0];

        vm.mockCall(
            address(vault), abi.encodeWithSignature("quarantinedAssets(address)", market), abi.encode(uint256(1))
        );
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: Vault market assets quarantined");
        vm.clearMockedCalls();

        _mockVaultConfig(market, MarketConfig({cap: 1, enabled: false, removableAt: 0}));
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: Vault cap remains");
        vm.clearMockedCalls();

        _mockVaultConfig(market, MarketConfig({cap: 0, enabled: false, removableAt: 1}));
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: pending Vault removal remains");
        vm.clearMockedCalls();

        vm.mockCall(
            address(vault),
            abi.encodeWithSignature("pendingCap(address)", market),
            abi.encode(PendingUint192({value: 1, validAt: 1}))
        );
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: pending Vault cap remains");
        vm.clearMockedCalls();

        vm.mockCall(address(vault), abi.encodeWithSignature("supplyQueueLength()"), abi.encode(uint256(2)));
        vm.mockCall(address(vault), abi.encodeWithSignature("supplyQueue(uint256)", 1), abi.encode(market));
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market remains in supply queue");
        vm.clearMockedCalls();

        _executeRecoveryAllocatorPlans();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertFalse(_isInWithdrawQueue(borrowMarkets[i]), "affected market remains in withdraw queue");
            assertFalse(vault.config(borrowMarkets[i]).enabled, "affected Vault config remains enabled");
        }
    }

    /// @dev Starts from Batch A containment, removes affected Vaults from the manifest and supplies zero-debt market state.
    /// It independently makes registry, market, leverage, swapper or periphery ownership invalid, or makes the market
    /// unfrozen, paused, without an oracle/adapter route, or without a leverage swapper. Batch C must reject each unsafe
    /// final-removal state before producing the Timelock recovery batch.
    function testBatchCRejectsUnsafeFinalRemovalStateAndOwnership() public {
        manifest.activationId = "batch-c-final-state-gates";
        _executeBatchA();
        delete manifest.vaults;
        address unauthorized = makeAddr("unauthorized-owner");

        _expectRecoveryStateRevert(
            address(marketRegistry),
            abi.encodeWithSignature("owner()"),
            abi.encode(unauthorized),
            "Batch C: Timelock does not own registry"
        );

        _expectRecoveryStateRevert(
            liquidationPeriphery,
            abi.encodeWithSignature("owner()"),
            abi.encode(unauthorized),
            "Batch C: Timelock does not own liquidation periphery"
        );

        _expectRecoveryStateRevert(
            borrowMarkets[0],
            abi.encodeWithSignature("paused(bytes32)", FROZEN_TYPE),
            abi.encode(false),
            "Batch C: market not frozen"
        );

        _expectRecoveryStateRevert(
            borrowMarkets[0],
            abi.encodeWithSignature("paused(bytes32)", PAUSE_TYPE),
            abi.encode(true),
            "Batch C: market paused"
        );

        _expectRecoveryStateRevert(
            borrowMarkets[0],
            abi.encodeCall(IMarketBase.oracle, ()),
            abi.encode(address(0)),
            "Batch C: market oracle unavailable"
        );

        _expectRecoveryStateRevert(
            address(altoAdapter),
            abi.encodeWithSignature("isApprovedContract(address)", borrowMarkets[0]),
            abi.encode(false),
            "Batch C: adapter route unavailable"
        );

        _expectRecoveryStateRevert(
            borrowMarkets[0],
            abi.encodeWithSignature("owner()"),
            abi.encode(unauthorized),
            "Batch C: Timelock does not own market"
        );

        _expectRecoveryStateRevert(
            leverages[0],
            abi.encodeWithSignature("owner()"),
            abi.encode(unauthorized),
            "Batch C: Timelock does not own leverage"
        );

        _expectRecoveryStateRevert(
            leverages[0], abi.encodeWithSignature("swapper()"), abi.encode(address(0)), "Batch C: zero leverage swapper"
        );

        _expectRecoveryStateRevert(
            leverageSwappers[0],
            abi.encodeWithSignature("owner()"),
            abi.encode(unauthorized),
            "Batch C: Timelock does not own leverage swapper"
        );
    }

    /// @dev Uses a one-market manifest with Medium severity and snapshots every omitted market before containment. It
    /// executes the complete ERP lifecycle for the selected market, including ordinary liquidation, real Vault
    /// reallocation, allocator cleanup and Batch C. The selected market must be recovered while all recorded Vault,
    /// registry, adapter and integration state of the omitted markets remains unchanged after every phase.
    function testMediumSeverityEndToEndResponseFromContainmentThroughRecovery() public {
        _snapshotOriginalSupplyQueue();
        _snapshotUnaffectedMarkets();
        uint256[] memory indexes = new uint256[](1);
        _selectManifestMarkets(indexes);

        manifest.activationId = "medium-end-to-end";
        _assertBorrowerListComplete(0);
        manifest.t0 = block.timestamp + 7 days;
        uint256 vaultSharesBefore = vaultToken.totalSupply();
        IMarket target = IMarket(borrowMarkets[0]);
        address originalIrm = target.irm();
        uint256 maxLtvBefore = target.maxLtv();

        _executeBatchA();
        assertEq(manifest.sourceBlock, block.number, "Batch A source state not synchronized");
        _assertAllFrozenAndUnpaused();
        _assertAllRequiredExitIntegrationsActive();
        _assertSupplyQueuePreservesUnaffectedOrder();
        _assertUnaffectedMarketsUnchanged();

        _advanceTo(manifest.t0);
        _executeFixedRatePhase();
        assertNotEq(target.irm(), originalIrm, "selected market IRM unchanged");
        _assertUnaffectedMarketsUnchanged();

        _executeMediumCorrectionsToZero(manifest.t0, "medium-end-to-end");
        assertTrue(_allDebtCleared(), "Medium lifecycle left market debt");
        assertLt(target.maxLtv(), maxLtvBefore, "selected market LTV unchanged");
        _assertUnaffectedMarketsUnchanged();

        address replacement = _exitSelectedMarketFromVault();
        _assertSelectedReplacementState(replacement, vaultSharesBefore);
        _assertUnaffectedMarketsUnchanged();
        _snapshotUnrelatedMarketState();

        _executeRecoveryAndAssertBatch();
        _assertMarketRemoved(0);
        _assertUnrelatedMarketStateUnchanged(0);
        _assertSelectedReplacementState(replacement, vaultSharesBefore);
        _assertUnaffectedMarketsUnchanged();
        assertGe(manifest.lastStepExecutedAt, manifest.t0 + 28 days, "Medium lifecycle did not reach terminal timing");
    }

    /// @dev Uses every configured market plus two real affected Vaults with different allocators. After correction and
    /// ordinary liquidation clear debt, it proves recovery rejects outstanding Vault supply and that an exit without a
    /// destination is invalid. It then reallocates into a real replacement, executes both allocator plans and the final
    /// Timelock batch, and verifies queue/config cleanup, integration removal, rerun safety and legacy user exit routes.
    function testBatchCRecoverSucceedsAfterDebtAndVaultMarketSupplyAreZero() public {
        manifest.activationId = "batch-c-success";
        _assertBorrowerListsComplete();
        IAltoVault secondVault = _addRecoveryVaultWithDifferentAllocator();
        uint256 vaultSharesBefore = vaultToken.totalSupply();
        _executePrerequisitePhases();

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: Vault market supply remains");

        uint256 targetSupplyAssets = _affectedVaultSupplyAssets();
        assertGt(targetSupplyAssets, 0, "test requires positive affected-market supply");
        MarketAllocation[] memory exitsWithoutReplacement = _targetExitAllocations(0);
        vm.expectRevert(IAltoVaultErrors.InconsistentReallocation.selector);
        vm.prank(manifest.vaults[0].allocator);
        vault.reallocate(exitsWithoutReplacement);

        address replacement = _approveRecoveryReplacementMarket(targetSupplyAssets + 1 ether);
        _reallocateVaultToReplacement(replacement);
        _executeRecoveryAllocatorPlans();
        _assertRecoveryPreconditions(replacement, vaultSharesBefore);
        _assertVaultQueueCleanup(secondVault);
        _disableSomeRecoveryIntegrations();
        _snapshotUnrelatedMarketState();

        _executeRecoveryAndAssertBatch();

        _assertRecoveryOutcome(replacement, vaultSharesBefore);

        // Recovery is state-derived: a completed rerun is a no-op and removes stale optional artifacts.
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, manifest, input);
        assertFalse(vm.exists(_artifactPath(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE)));
        assertFalse(vm.exists(_artifactPath(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_EXECUTE_FILE)));
        _assertRecoveryOutcome(replacement, vaultSharesBefore);

        _exerciseVaultDepositAndWithdrawal(replacement, vaultSharesBefore);
        _exerciseLegacyExitRoutes();
    }

    function _addRecoveryVaultWithDifferentAllocator() private returns (IAltoVault secondVault) {
        address secondCurator = makeAddr("batch-c-second-curator");
        address secondAllocator = makeAddr("batch-c-second-allocator");
        secondVault = IAltoVault(
            address(
                new AltoVault({
                    owner: address(this),
                    initialTimelock: 1 days,
                    _asset: vaultToken.asset(),
                    __name: "Batch C DUSD Vault",
                    __symbol: "bcDUSD",
                    _marketRegistry: address(marketRegistry)
                })
            )
        );
        secondVault.setCurator(secondCurator);
        secondVault.setIsAllocator(secondAllocator, true);

        address[] memory supplyQueue = new address[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            vm.prank(secondCurator);
            secondVault.submitCap(borrowMarkets[i], i + 1);
            supplyQueue[i] = borrowMarkets[i];
        }
        vm.warp(secondVault.pendingCap(borrowMarkets[0]).validAt);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            secondVault.acceptCap(borrowMarkets[i]);
        }
        vm.prank(secondAllocator);
        secondVault.setSupplyQueue(supplyQueue);

        BorrowMarketOffboardingVault memory productionVault = manifest.vaults[0];
        delete manifest.vaults;
        _pushManifestVault(productionVault);
        _pushManifestVault(
            BorrowMarketOffboardingVault({
                allocator: secondAllocator,
                maxVaultLossAssets: 0,
                reallocationBufferAssets: 1 ether,
                replacementMarkets: new address[](0),
                vault: address(secondVault)
            })
        );
    }

    function _assertVaultQueueCleanup(IAltoVault affectedVault) private view {
        assertEq(affectedVault.supplyQueueLength(), 0, "second Vault supply queue not cleared");
        for (uint256 i; i < affectedVault.withdrawQueueLength(); ++i) {
            assertFalse(_isAffectedMarket(affectedVault.withdrawQueue(i)), "affected market remains in withdraw queue");
        }
        for (uint256 i; i < borrowMarkets.length; ++i) {
            MarketConfig memory config = affectedVault.config(borrowMarkets[i]);
            assertFalse(config.enabled, "second Vault config remains enabled");
            assertEq(config.cap, 0, "second Vault cap remains");
        }
    }

    function _expectRecoveryStateRevert(
        address target,
        bytes memory callData,
        bytes memory returnData,
        string memory reason
    ) private {
        _mockZeroDebt();
        vm.mockCall(target, callData, returnData);
        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, reason);
    }

    function _mockZeroDebt() private {
        vm.clearMockedCalls();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            vm.mockCall(
                borrowMarkets[i], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
            );
        }
    }

    function _mockVaultConfig(address market, MarketConfig memory config) private {
        vm.mockCall(address(vault), abi.encodeWithSignature("config(address)", market), abi.encode(config));
    }

    function _executeRecoveryAndAssertBatch() private {
        uint256 expectedCallCount = _outstandingRecoveryCallCount();
        assertGt(expectedCallCount, 0, "test requires outstanding recovery calls");

        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_C_RECOVER;
        input = scriptHarness.runPhase(phase, manifest, input);
        for (uint256 i; i < manifest.vaults.length; ++i) {
            string memory allocatorFile =
                BorrowMarketOffboarding.vaultAllocatorFileName(phase, manifest.vaults[i].vault);
            assertFalse(vm.exists(_artifactPath(phase, allocatorFile)), "stale Batch C allocator plan remains");
        }
        _assertRecoveryBatch(_artifactPath(phase, RECOVER_EXECUTE_FILE), expectedCallCount);
        _executeTimelockArtifacts(phase, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);
    }

    function _assertRecoveryBatch(string memory executePath, uint256 expectedCallCount) private view {
        string memory json = vm.readFile(executePath);
        (address target, bytes memory data) = _jsonTransaction(json, 0);
        assertEq(target, address(timelock), "recovery execute target is not Timelock");
        assertFalse(_jsonTransactionExists(json, 1), "recovery execute file has multiple Safe transactions");
        assertEq(
            _selector(data),
            bytes4(keccak256("executeBatch(address[],uint256[],bytes[],bytes32,bytes32)")),
            "wrong Timelock execute selector"
        );

        bytes memory arguments = new bytes(data.length - 4);
        for (uint256 i; i < arguments.length; ++i) {
            arguments[i] = data[i + 4];
        }
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads,
            bytes32 predecessor,
            bytes32 salt
        ) = abi.decode(arguments, (address[], uint256[], bytes[], bytes32, bytes32));

        assertEq(targets.length, expectedCallCount, "recovery did not include exactly the outstanding removals");
        assertEq(values.length, targets.length, "recovery values length mismatch");
        assertEq(payloads.length, targets.length, "recovery payloads length mismatch");
        assertEq(predecessor, bytes32(0), "unexpected recovery predecessor");
        assertEq(salt, bytes32(0), "unexpected recovery salt");

        bool reachedRegistryRemovals;
        for (uint256 i; i < targets.length; ++i) {
            assertEq(values[i], 0, "recovery call sends ETH");
            if (targets[i] == address(marketRegistry)) {
                reachedRegistryRemovals = true;
                assertEq(
                    _selector(payloads[i]),
                    IMarketRegistry.removeBorrowMarket.selector,
                    "unexpected registry recovery call"
                );
            } else {
                assertFalse(reachedRegistryRemovals, "integration removal appears after registry removal");
            }
        }
        assertTrue(reachedRegistryRemovals, "recovery has no registry removals");
    }

    function _outstandingRecoveryCallCount() private view returns (uint256 count) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            AltoLeverage leverage = AltoLeverage(leverages[i]);
            IAltoLeverageSwapper swapper = IAltoLeverageSwapper(leverageSwappers[i]);

            if (leverage.supportedMarkets(address(market))) ++count;
            if (market.authorizedCallbacks(address(leverage))) ++count;
            if (swapper.isWhitelisted(address(leverage))) ++count;
            if (ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(address(market))) ++count;
            if (market.authorizedLiquidationPeriphery(liquidationPeriphery)) ++count;
            if (marketRegistry.isBorrowMarket(address(market))) ++count;
        }
    }

    function _disableSomeRecoveryIntegrations() private {
        assertGe(borrowMarkets.length, 5, "test requires five affected markets");

        vm.startPrank(address(timelock));
        marketRegistry.removeBorrowMarket(borrowMarkets[0]);
        AltoLeverage(leverages[1]).setMarket(borrowMarkets[1], false);
        IMarketBase(borrowMarkets[2]).setAuthorizedCallback(leverages[2], false);
        IAltoLeverageSwapper(leverageSwappers[3]).setWhitelisted(leverages[3], false);
        ILiquidationPeripheryBase(liquidationPeriphery).setSupportedMarket(borrowMarkets[4], false);
        IMarketBase(borrowMarkets[0]).setAuthorizedLiquidationPeriphery(liquidationPeriphery, false);
        vm.stopPrank();
    }

    function _approveRecoveryReplacementMarket(uint256 supplyCap) private returns (address replacement) {
        assertTrue(vault.isAllocator(manifest.vaults[0].allocator), "configured allocator is not authorized");
        _assertVaultQueuesReadyForExit();
        return _deployAndApproveReplacementBorrowMarket(supplyCap);
    }

    function _executePrerequisitePhases() private {
        _executeBatchBToZeroDebt();
        _assertAllFrozenAndUnpaused();
    }

    function _assertBorrowerListsComplete() private view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertBorrowerListComplete(i);
        }
    }

    function _assertVaultQueuesReadyForExit() private view {
        assertEq(vault.supplyQueueLength(), 0, "affected markets remain in supply queue");
        assertGe(vault.withdrawQueueLength(), borrowMarkets.length, "affected withdraw queue entries missing");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertTrue(_isInWithdrawQueue(borrowMarkets[i]), "affected market missing from withdraw queue");
        }
    }

    function _assertReplacementVaultState(address replacement, uint256 vaultSharesBefore) private view {
        assertEq(vault.supplyQueueLength(), 1, "unexpected Vault supply queue length");
        assertEq(vault.supplyQueue(0), replacement, "replacement missing from supply queue");
        assertTrue(_isInWithdrawQueue(replacement), "replacement missing from withdraw queue");
        assertEq(vaultToken.totalSupply(), vaultSharesBefore, "Vault ERC4626 supply changed");
        MarketConfig memory config = vault.config(replacement);
        assertTrue(marketRegistry.isBorrowMarket(replacement), "replacement is not registered");
        assertTrue(config.enabled, "replacement is not enabled");
        assertGt(config.cap, 0, "replacement has no approved cap");
        assertGt(IMarket(replacement).position(address(vault)).supplyShares, 0, "replacement has no Vault supply");
        assertEq(vault.lostAssets(), 0, "Vault has realized losses");
    }

    function _assertRecoveryPreconditions(address replacement, uint256 vaultSharesBefore) private view {
        _assertReplacementVaultState(replacement, vaultSharesBefore);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            _assertVaultExitState(market);

            _assertRequiredExitIntegrationsActive(i);
            _assertFrozenAndUnpaused(market);
        }
    }

    function _snapshotUnrelatedMarketState() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _snapshotUnrelatedMarketState(i);
        }
    }

    function _snapshotUnrelatedMarketState(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address[] memory borrowers = _forkBorrowers(marketIndex);
        address legacyUser;
        Position memory legacyPosition;
        for (uint256 i; i < borrowers.length; ++i) {
            Position memory candidate = market.position(borrowers[i]);
            if (candidate.supplyShares != 0 && candidate.collateralAssets != 0) {
                legacyUser = borrowers[i];
                legacyPosition = candidate;
                break;
            }
        }
        assertNotEq(legacyUser, address(0), "no representative legacy position");

        address irm = market.irm();
        address liquidationEngine = market.liquidationEngine();
        (uint256 borrowRate,) = FixedRateIrm(irm).irState();
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();

        recoverySnapshots.push(
            RecoveryMarketSnapshot({
                oracle: market.oracle(),
                irm: irm,
                liquidationEngine: liquidationEngine,
                feeRecipient: market.feeRecipient(),
                maxLtv: market.maxLtv(),
                borrowOpeningFee: market.borrowOpeningFee(),
                borrowRate: borrowRate,
                liquidationConfigurationHash: keccak256(abi.encode(liquidationConfiguration)),
                totalSupply: market.totalSupply(),
                legacyUser: legacyUser,
                legacyPosition: legacyPosition
            })
        );
    }

    function _assertRecoveryOutcome(address replacement, uint256 vaultSharesBefore) private view {
        _assertReplacementVaultState(replacement, vaultSharesBefore);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketRemoved(i);
            _assertUnrelatedMarketStateUnchanged(i);
        }
    }

    function _exerciseVaultDepositAndWithdrawal(address replacement, uint256 vaultSharesBefore) private {
        address user = makeAddr("replacement-vault-user");
        IERC20 asset = IERC20(vaultToken.asset());
        uint256 assets = 1 ether;
        deal(address(asset), user, assets);

        vm.startPrank(user);
        asset.approve(address(vaultToken), assets);
        uint256 shares = vaultToken.deposit(assets, user);
        assertGt(shares, 0, "Vault deposit minted no shares");
        uint256 withdrawnAssets = vaultToken.redeem(shares, user, user);
        vm.stopPrank();

        assertGt(withdrawnAssets, 0, "Vault redemption withdrew no assets");
        assertEq(vaultToken.balanceOf(user), 0, "test Vault shares remain");
        _assertReplacementVaultState(replacement, vaultSharesBefore);
    }

    function _assertVaultExitState(IMarket market) private view {
        Balance memory debt = market.totalBorrowed();
        MarketConfig memory config = vault.config(address(market));
        PendingUint192 memory pendingCap = vault.pendingCap(address(market));

        assertEq(debt.assets, 0, "market borrowed assets remain");
        assertEq(debt.shares, 0, "market borrowed shares remain");
        assertEq(market.position(address(vault)).supplyShares, 0, "Vault market supply remains");
        assertEq(vault.quarantinedAssets(address(market)), 0, "Vault market assets are quarantined");
        assertEq(config.cap, 0, "Vault cap is non-zero");
        assertFalse(config.enabled, "Vault market remains enabled");
        assertEq(config.removableAt, 0, "Vault removal remains pending");
        assertEq(pendingCap.value, 0, "pending Vault cap value remains");
        assertEq(pendingCap.validAt, 0, "pending Vault cap remains");
    }

    function _assertMarketRemoved(uint256 marketIndex) private view {
        _assertVaultExitState(IMarket(borrowMarkets[marketIndex]));
        _assertRecoveryRoutesRemoved(marketIndex);
    }

    function _assertUnrelatedMarketStateUnchanged(uint256 marketIndex) private view {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        RecoveryMarketSnapshot memory beforeState = recoverySnapshots[marketIndex];
        Balance memory supply = market.totalSupply();
        Position memory legacyPosition = market.position(beforeState.legacyUser);
        (uint256 borrowRate,) = FixedRateIrm(beforeState.irm).irState();
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(beforeState.liquidationEngine).liquidationConfiguration();

        assertEq(market.oracle(), beforeState.oracle, "oracle changed");
        assertEq(market.irm(), beforeState.irm, "IRM changed");
        assertEq(market.liquidationEngine(), beforeState.liquidationEngine, "liquidation engine changed");
        assertEq(market.feeRecipient(), beforeState.feeRecipient, "fee recipient changed");
        assertEq(market.maxLtv(), beforeState.maxLtv, "market max LTV changed");
        assertEq(market.borrowOpeningFee(), beforeState.borrowOpeningFee, "borrow opening fee changed");
        assertEq(borrowRate, beforeState.borrowRate, "fixed borrow rate changed");
        assertEq(
            keccak256(abi.encode(liquidationConfiguration)),
            beforeState.liquidationConfigurationHash,
            "liquidation configuration changed"
        );
        assertEq(supply.assets, beforeState.totalSupply.assets, "unrelated market supply assets changed");
        assertEq(supply.shares, beforeState.totalSupply.shares, "unrelated market supply shares changed");
        assertEq(legacyPosition.supplyShares, beforeState.legacyPosition.supplyShares, "legacy supply changed");
        assertEq(legacyPosition.borrowShares, 0, "legacy debt returned");
        assertEq(
            legacyPosition.collateralAssets, beforeState.legacyPosition.collateralAssets, "legacy collateral changed"
        );
    }

    function _exerciseLegacyExitRoutes() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            RecoveryMarketSnapshot memory beforeState = recoverySnapshots[i];
            vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(initialOraclePrices[i]));

            vm.startPrank(beforeState.legacyUser);
            market.removeSupply(
                0, beforeState.legacyPosition.supplyShares, beforeState.legacyUser, beforeState.legacyUser
            );
            market.removeCollateral(
                beforeState.legacyPosition.collateralAssets, beforeState.legacyUser, beforeState.legacyUser, ""
            );
            vm.stopPrank();

            Position memory afterExit = market.position(beforeState.legacyUser);
            assertEq(afterExit.supplyShares, 0, "legacy removeSupply failed");
            assertEq(afterExit.borrowShares, 0, "legacy debt changed during exit");
            assertEq(afterExit.collateralAssets, 0, "legacy removeCollateral failed");
            _assertFrozenAndUnpaused(market);
        }
    }

    function _exitSelectedMarketFromVault() private returns (address replacement) {
        IMarket target = _targetMarket();
        uint256 targetSupplyAssets = address(target).expectedSupplyAssets(address(vault));
        assertGt(targetSupplyAssets, 0, "test requires selected-market Vault supply");

        replacement = _deployAndApproveReplacementBorrowMarket(targetSupplyAssets + 1 ether);
        _restoreUnaffectedSupplyQueue(replacement);

        MarketAllocation[] memory allocations = new MarketAllocation[](2);
        allocations[0] = MarketAllocation({market: address(target), assets: 0});
        allocations[1] = MarketAllocation({market: replacement, assets: type(uint256).max});
        vm.prank(manifest.vaults[0].allocator);
        vault.reallocate(allocations);

        address[] memory expectedWithdrawQueue = _withdrawQueueWithout(address(target));
        _executeRecoveryAllocatorPlans();
        assertEq(vault.withdrawQueueLength(), expectedWithdrawQueue.length, "unexpected withdraw queue length");
        for (uint256 i; i < expectedWithdrawQueue.length; ++i) {
            assertEq(vault.withdrawQueue(i), expectedWithdrawQueue[i], "unaffected withdraw queue order changed");
        }
        assertEq(target.position(address(vault)).supplyShares, 0, "selected-market Vault supply remains");
        assertFalse(_isInSupplyQueue(address(target)), "selected market remains in supply queue");
        assertFalse(_isInWithdrawQueue(address(target)), "selected market remains in withdraw queue");

        MarketConfig memory config = vault.config(address(target));
        assertEq(config.cap, 0, "selected-market Vault cap remains");
        assertFalse(config.enabled, "selected market remains enabled in Vault");
        assertEq(config.removableAt, 0, "selected-market removal remains pending");
        PendingUint192 memory pendingCap = vault.pendingCap(address(target));
        assertEq(pendingCap.validAt, 0, "selected-market cap remains pending");
    }

    function _assertSupplyQueuePreservesUnaffectedOrder() private view {
        address target = address(_targetMarket());
        uint256 expectedIndex;
        for (uint256 i; i < originalSupplyQueue.length; ++i) {
            if (originalSupplyQueue[i] == target) continue;
            assertEq(
                vault.supplyQueue(expectedIndex++), originalSupplyQueue[i], "unaffected supply queue order changed"
            );
        }
        assertEq(vault.supplyQueueLength(), expectedIndex, "unexpected supply queue length");
    }

    function _withdrawQueueWithout(address target) private view returns (address[] memory expectedQueue) {
        uint256 queueLength = vault.withdrawQueueLength();
        uint256 unaffectedCount;
        for (uint256 i; i < queueLength; ++i) {
            if (vault.withdrawQueue(i) != target) ++unaffectedCount;
        }

        expectedQueue = new address[](unaffectedCount);
        uint256 expectedIndex;
        for (uint256 i; i < queueLength; ++i) {
            address market = vault.withdrawQueue(i);
            if (market != target) expectedQueue[expectedIndex++] = market;
        }
    }

    function _restoreUnaffectedSupplyQueue(address replacement) private {
        address target = address(_targetMarket());
        uint256 unaffectedCount;
        for (uint256 i; i < originalSupplyQueue.length; ++i) {
            if (originalSupplyQueue[i] != target) ++unaffectedCount;
        }

        address[] memory supplyQueue = new address[](unaffectedCount + 1);
        uint256 index;
        for (uint256 i; i < originalSupplyQueue.length; ++i) {
            if (originalSupplyQueue[i] != target) supplyQueue[index++] = originalSupplyQueue[i];
        }
        supplyQueue[index] = replacement;

        vm.prank(manifest.vaults[0].allocator);
        vault.setSupplyQueue(supplyQueue);
    }

    function _snapshotOriginalSupplyQueue() private {
        for (uint256 i; i < vault.supplyQueueLength(); ++i) {
            originalSupplyQueue.push(vault.supplyQueue(i));
        }
    }

    function _snapshotUnaffectedMarkets() private {
        for (uint256 i = 1; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            address leverage = leverages[i];
            address swapper = leverageSwappers[i];
            LiquidationConfiguration memory configuration =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
            Position memory vaultPosition = market.position(address(vault));

            unaffectedMarkets.push(
                UnaffectedMarketSnapshot({
                    market: address(market),
                    leverage: leverage,
                    swapper: swapper,
                    irm: market.irm(),
                    maxLtv: market.maxLtv(),
                    liquidationConfigurationHash: keccak256(abi.encode(configuration)),
                    totalSupply: market.totalSupply(),
                    totalBorrowed: market.totalBorrowed(),
                    vaultSupplyShares: vaultPosition.supplyShares,
                    vaultConfigurationHash: _vaultConfigurationHash(address(market)),
                    frozen: market.paused(FROZEN_TYPE),
                    paused: market.paused(PAUSE_TYPE),
                    registered: marketRegistry.isBorrowMarket(address(market)),
                    adapterApproved: altoAdapter.isApprovedContract(address(market)),
                    leverageSupported: AltoLeverage(leverage).supportedMarkets(address(market)),
                    callbackAuthorized: market.authorizedCallbacks(leverage),
                    swapperWhitelisted: IAltoLeverageSwapper(swapper).isWhitelisted(leverage),
                    peripherySupported: ILiquidationPeripheryBase(liquidationPeriphery)
                        .supportedMarkets(address(market)),
                    peripheryAuthorized: market.authorizedLiquidationPeriphery(liquidationPeriphery),
                    inSupplyQueue: _isInSupplyQueue(address(market)),
                    inWithdrawQueue: _isInWithdrawQueue(address(market))
                })
            );
        }
    }

    function _assertUnaffectedMarketsUnchanged() private view {
        for (uint256 i; i < unaffectedMarkets.length; ++i) {
            UnaffectedMarketSnapshot memory beforeState = unaffectedMarkets[i];
            IMarket market = IMarket(beforeState.market);
            LiquidationConfiguration memory configuration =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
            Balance memory totalSupply = market.totalSupply();
            Balance memory totalBorrowed = market.totalBorrowed();

            assertEq(market.irm(), beforeState.irm, "unaffected market IRM changed");
            assertEq(market.maxLtv(), beforeState.maxLtv, "unaffected market LTV changed");
            assertEq(
                keccak256(abi.encode(configuration)),
                beforeState.liquidationConfigurationHash,
                "unaffected liquidation configuration changed"
            );
            assertEq(totalSupply.assets, beforeState.totalSupply.assets, "unaffected supply assets changed");
            assertEq(totalSupply.shares, beforeState.totalSupply.shares, "unaffected supply shares changed");
            assertEq(totalBorrowed.assets, beforeState.totalBorrowed.assets, "unaffected borrow assets changed");
            assertEq(totalBorrowed.shares, beforeState.totalBorrowed.shares, "unaffected borrow shares changed");
            assertEq(
                market.position(address(vault)).supplyShares,
                beforeState.vaultSupplyShares,
                "unaffected Vault supply changed"
            );
            assertEq(
                _vaultConfigurationHash(address(market)),
                beforeState.vaultConfigurationHash,
                "unaffected Vault configuration changed"
            );
            assertEq(market.paused(FROZEN_TYPE), beforeState.frozen, "unaffected frozen state changed");
            assertEq(market.paused(PAUSE_TYPE), beforeState.paused, "unaffected pause state changed");
            assertEq(
                marketRegistry.isBorrowMarket(address(market)),
                beforeState.registered,
                "unaffected registry state changed"
            );
            assertEq(
                altoAdapter.isApprovedContract(address(market)),
                beforeState.adapterApproved,
                "unaffected adapter approval changed"
            );
            assertEq(
                AltoLeverage(beforeState.leverage).supportedMarkets(address(market)),
                beforeState.leverageSupported,
                "unaffected leverage support changed"
            );
            assertEq(
                market.authorizedCallbacks(beforeState.leverage),
                beforeState.callbackAuthorized,
                "unaffected callback authorization changed"
            );
            assertEq(
                IAltoLeverageSwapper(beforeState.swapper).isWhitelisted(beforeState.leverage),
                beforeState.swapperWhitelisted,
                "unaffected swapper permission changed"
            );
            assertEq(
                ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(address(market)),
                beforeState.peripherySupported,
                "unaffected periphery support changed"
            );
            assertEq(
                market.authorizedLiquidationPeriphery(liquidationPeriphery),
                beforeState.peripheryAuthorized,
                "unaffected periphery authorization changed"
            );
            assertEq(_isInSupplyQueue(address(market)), beforeState.inSupplyQueue, "unaffected supply queue changed");
            assertEq(
                _isInWithdrawQueue(address(market)), beforeState.inWithdrawQueue, "unaffected withdraw queue changed"
            );
        }
    }

    function _vaultConfigurationHash(address market) private view returns (bytes32) {
        return keccak256(abi.encode(vault.config(market), vault.pendingCap(market), vault.quarantinedAssets(market)));
    }

    function _targetMarket() private view returns (IMarket) {
        return IMarket(manifest.markets[0].market);
    }

    function _assertSelectedReplacementState(address replacement, uint256 vaultSharesBefore) private view {
        MarketConfig memory config = vault.config(replacement);
        assertTrue(marketRegistry.isBorrowMarket(replacement), "replacement is not registered");
        assertTrue(config.enabled, "replacement is not enabled");
        assertGt(config.cap, 0, "replacement has no approved cap");
        assertGt(IMarket(replacement).position(address(vault)).supplyShares, 0, "replacement has no Vault supply");
        assertTrue(_isInSupplyQueue(replacement), "replacement missing from supply queue");
        assertTrue(_isInWithdrawQueue(replacement), "replacement missing from withdraw queue");
        assertEq(vaultToken.totalSupply(), vaultSharesBefore, "Vault ERC4626 supply changed");
        assertEq(vault.lostAssets(), 0, "Vault has realized losses");
    }
}
