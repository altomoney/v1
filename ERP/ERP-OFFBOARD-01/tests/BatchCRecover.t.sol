// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MintMarketOffboardingTestBase} from "./MintMarketOffboardingTestBase.sol";
import {MintMarketOffboardingPhase} from "../IMintMarketOffboarding.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {Call} from "@morpho-org/bundler3/interfaces/IBundler3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MintBatchCRecoverTest is MintMarketOffboardingTestBase {
    struct RecoveryMarketSnapshot {
        address oracle;
        uint256 badDebtAssets;
        uint256 mintedAssets;
    }

    AltoAdapter internal altoAdapter;
    address internal liquidationPeriphery;

    function setUp() public {
        _setUpManifest();
        altoAdapter = AltoAdapter(payable(input.contracts.altoAdapter));
        liquidationPeriphery = input.contracts.liquidationPeriphery;
    }

    /// @dev Generates Batch A, fixed-rate, and rate/LTV correction prerequisites through ordinary liquidations, then
    /// verifies and executes the exact recovery batch and exercises the retained adapter withdrawal route.
    function testBatchCRecoverGeneratesAndExecutesExactMintRemoval() public {
        uint256 retainedOraclePrice = IOracle(IMarket(mintMarkets[0]).oracle()).getPrice();
        _prepareRecoveryTerminalState("mint-recovery-success");
        _disableSomeRecoveryIntegrations();

        RecoveryMarketSnapshot[] memory beforeState = _snapshotRecoveryState();
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_C_RECOVER;
        input = scriptHarness.runPhase(phase, manifest, input);
        (bytes32 operationId,) = _assertGeneratedRecoveryArtifacts();
        bytes32 executedOperationId = _executeTimelockArtifacts(phase, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);
        assertEq(executedOperationId, operationId, "executed recovery operation mismatch");

        _assertRecoveryOutcome(beforeState);
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertEntrancesBlocked(i);
        }

        input = scriptHarness.runPhase(phase, manifest, input);
        (bytes32 rerunOperationId, uint256 rerunCallCount) = _assertGeneratedRecoveryArtifacts();
        assertEq(rerunCallCount, mintMarkets.length * 4, "recovery rerun has conditional calls");
        assertNotEq(rerunOperationId, operationId, "recovery rerun reused completed operation");
        executedOperationId = _executeTimelockArtifacts(phase, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);
        assertEq(executedOperationId, rerunOperationId, "executed recovery rerun mismatch");
        _assertRecoveryOutcome(beforeState);

        _exerciseRetainedAdapterWithdrawal(0, retainedOraclePrice);
    }

    /// @dev Independently supplies one residual borrow share or one residual borrowed asset and verifies ordinary recovery
    /// cannot begin until both terminal market-debt values are zero.
    function testBatchCRequiresBothZeroDebtTargets() public {
        _prepareContainedMarkets("mint-recovery-debt-gates");

        vm.mockCall(
            mintMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 1}))
        );
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market debt remains");

        vm.clearMockedCalls();
        vm.mockCall(
            mintMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 1, shares: 0}))
        );
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market debt remains");
    }

    /// @dev Starts from the real ordinary terminal state and verifies recovery rejects fees, unapproved bad debt or DUSD,
    /// an unsafe pause state, and missing oracle or AltoAdapter withdrawal support.
    function testBatchCRejectsIncompleteOrUnsafeRecoveryState() public {
        _prepareRecoveryTerminalState("mint-recovery-state-gates");
        address market = mintMarkets[0];

        vm.mockCall(market, abi.encodeWithSignature("claimableFeesAssets()"), abi.encode(uint256(1)));
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: claimable fees remain");
        vm.clearMockedCalls();

        vm.mockCall(
            market,
            abi.encodeWithSignature("badDebtAssets()"),
            abi.encode(manifest.markets[0].approvedRecoveryBadDebtAssets + 1)
        );
        _expectPhaseRevert(
            MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: bad debt does not match approved residual"
        );
        vm.clearMockedCalls();

        vm.mockCall(
            address(dusd),
            abi.encodeCall(IDUSD.minterConfig, (market)),
            abi.encode(manifest.markets[0].maxUnbackedDusdAssets + 1, uint256(0))
        );
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: unbacked DUSD exceeds approved limit");
        vm.clearMockedCalls();

        uint256 snapshotId = vm.snapshotState();
        vm.prank(manifest.freezerSafe);
        IPausable(market).pause(FROZEN_TYPE, false);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market not frozen");
        assertTrue(vm.revertToState(snapshotId), "failed to restore unfrozen gate");

        snapshotId = vm.snapshotState();
        vm.prank(manifest.freezerSafe);
        IPausable(market).pause(PAUSE_TYPE, true);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market paused");
        assertTrue(vm.revertToState(snapshotId), "failed to restore paused gate");

        vm.mockCall(market, abi.encodeCall(IMarketBase.oracle, ()), abi.encode(address(0)));
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: market oracle unavailable");
        vm.clearMockedCalls();

        vm.prank(address(timelock));
        altoAdapter.revokeContract(market);
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: adapter route unavailable");
    }

    /// @dev Creates real governance-liquidation bad debt and residual market-attributed DUSD, rejects mismatched bad-debt
    /// approval and insufficient DUSD allowance, then recovers with the debt ceiling equal to live bad debt.
    function testBatchCRecoversApprovedExceptionalBadDebtAndDusdResidual() public {
        _prepareContainedMarkets("mint-recovery-exceptional");
        address marketAddress = mintMarkets[0];
        address borrower = _seededBorrower(0);
        _claimFeesAndRepayAll(marketAddress, borrower);

        vm.prank(address(timelock));
        IMarket(marketAddress).governanceLiquidate(borrower, true);
        _approveCurrentRecoveryResiduals();

        Balance memory borrowed = IMarket(marketAddress).totalBorrowed();
        uint256 badDebtAssets = AltoMintMarket(marketAddress).badDebtAssets();
        (uint256 mintedBefore,) = dusd.minterConfig(marketAddress);
        assertEq(borrowed.assets, 0, "exceptional borrowed assets remain");
        assertEq(borrowed.shares, 0, "exceptional borrowed shares remain");
        assertGt(badDebtAssets, 0, "exceptional path created no bad debt");
        assertGt(mintedBefore, 0, "exceptional path created no DUSD residual");
        assertEq(AltoMintMarket(marketAddress).claimableFeesAssets(), 0, "exceptional fees remain");

        manifest.markets[0].approvedRecoveryBadDebtAssets = badDebtAssets - 1;
        manifest.markets[0].maxUnbackedDusdAssets = mintedBefore;
        _expectPhaseRevert(
            MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: bad debt does not match approved residual"
        );

        manifest.markets[0].approvedRecoveryBadDebtAssets = badDebtAssets + 1;
        _expectPhaseRevert(
            MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: bad debt does not match approved residual"
        );

        manifest.markets[0].approvedRecoveryBadDebtAssets = badDebtAssets;
        manifest.markets[0].maxUnbackedDusdAssets = mintedBefore - 1;
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_C_RECOVER, "Batch C: unbacked DUSD exceeds approved limit");

        manifest.markets[0].maxUnbackedDusdAssets = mintedBefore;
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_C_RECOVER;
        input = scriptHarness.runPhase(phase, manifest, input);
        _assertGeneratedRecoveryArtifacts();
        _executeTimelockArtifacts(phase, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);

        Balance memory supply = IMarket(marketAddress).totalSupply();
        (uint256 mintedAfter, uint256 ceilingAfter) = dusd.minterConfig(marketAddress);
        assertEq(supply.assets, badDebtAssets, "exceptional debt ceiling does not equal bad debt");
        assertEq(mintedAfter, mintedBefore, "exceptional DUSD residual changed");
        assertEq(ceilingAfter, 0, "exceptional DUSD ceiling remains");
        assertFalse(dusd.allowedMinter(marketAddress), "exceptional minter remains enabled");
        assertFalse(dusd.allowedBurner(marketAddress), "exceptional burner remains enabled");
        assertTrue(altoAdapter.isApprovedContract(marketAddress), "exceptional adapter route removed");
        _assertFrozenAndUnpaused(IMarketBase(marketAddress));
    }

    function _assertGeneratedRecoveryArtifacts() private view returns (bytes32 operationId, uint256 callCount) {
        TimelockArtifactBatch memory scheduled;
        (scheduled, operationId) = _loadAndAssertTimelockPair(
            MintMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE, bytes32(0)
        );
        _assertRecoveryCalls(scheduled);
        callCount = scheduled.targets.length;
    }

    function _assertRecoveryCalls(TimelockArtifactBatch memory batch) private view {
        uint256 callIndex;
        for (uint256 i; i < mintMarkets.length; ++i) {
            address market = mintMarkets[i];
            _assertTimelockCall(
                batch,
                callIndex++,
                market,
                abi.encodeCall(AltoMintMarket.setDebtCeiling, (AltoMintMarket(market).badDebtAssets()))
            );
            _assertTimelockCall(batch, callIndex++, address(dusd), abi.encodeCall(IDUSD.setMinterCeiling, (market, 0)));
            _assertTimelockCall(
                batch, callIndex++, address(dusd), abi.encodeCall(IDUSD.setMinterStatus, (market, false))
            );
            _assertTimelockCall(
                batch, callIndex++, address(dusd), abi.encodeCall(IDUSD.setBurnerStatus, (market, false))
            );
        }

        for (uint256 i; i < mintMarkets.length; ++i) {
            address market = mintMarkets[i];
            AltoLeverage leverage = AltoLeverage(manifest.markets[i].leverage);
            IAltoLeverageSwapper swapper = leverage.swapper();
            if (leverage.supportedMarkets(market)) {
                _assertTimelockCall(
                    batch, callIndex++, address(leverage), abi.encodeCall(AltoLeverage.setMarket, (market, false))
                );
            }
            if (IMarket(market).authorizedCallbacks(address(leverage))) {
                _assertTimelockCall(
                    batch,
                    callIndex++,
                    market,
                    abi.encodeCall(IMarketBase.setAuthorizedCallback, (address(leverage), false))
                );
            }
            if (swapper.isWhitelisted(address(leverage))) {
                _assertTimelockCall(
                    batch,
                    callIndex++,
                    address(swapper),
                    abi.encodeCall(IAltoLeverageSwapper.setWhitelisted, (address(leverage), false))
                );
            }
        }

        for (uint256 i; i < mintMarkets.length; ++i) {
            address market = mintMarkets[i];
            if (ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(market)) {
                _assertTimelockCall(
                    batch,
                    callIndex++,
                    liquidationPeriphery,
                    abi.encodeCall(ILiquidationPeripheryBase.setSupportedMarket, (market, false))
                );
            }
            if (IMarket(market).authorizedLiquidationPeriphery(liquidationPeriphery)) {
                _assertTimelockCall(
                    batch,
                    callIndex++,
                    market,
                    abi.encodeCall(IMarketBase.setAuthorizedLiquidationPeriphery, (liquidationPeriphery, false))
                );
            }
        }

        for (uint256 i; i < mintMarkets.length; ++i) {
            address market = mintMarkets[i];
            if (!marketRegistry.isMintMarket(market)) continue;
            _assertTimelockCall(
                batch, callIndex++, address(marketRegistry), abi.encodeCall(IMarketRegistry.removeMintMarket, (market))
            );
        }

        _assertTimelockCallCount(batch, callIndex);
        bool reachedRegistryRemovals;
        for (uint256 i; i < batch.targets.length; ++i) {
            assertNotEq(batch.targets[i], address(altoAdapter), "recovery revokes AltoAdapter approval");
            for (uint256 j; j < mintMarkets.length; ++j) {
                assertNotEq(batch.targets[i], IMarket(mintMarkets[j]).oracle(), "recovery mutates oracle");
            }
            if (batch.targets[i] == address(marketRegistry)) reachedRegistryRemovals = true;
            else assertFalse(reachedRegistryRemovals, "non-registry call follows registry removal");
        }
    }

    function _disableSomeRecoveryIntegrations() private {
        vm.startPrank(address(timelock));
        marketRegistry.removeMintMarket(mintMarkets[0]);
        AltoLeverage(manifest.markets[1].leverage).setMarket(mintMarkets[1], false);
        IMarketBase(mintMarkets[2]).setAuthorizedCallback(manifest.markets[2].leverage, false);
        AltoLeverage leverage = AltoLeverage(manifest.markets[3].leverage);
        leverage.swapper().setWhitelisted(address(leverage), false);
        ILiquidationPeripheryBase(liquidationPeriphery).setSupportedMarket(mintMarkets[4], false);
        IMarketBase(mintMarkets[5]).setAuthorizedLiquidationPeriphery(liquidationPeriphery, false);
        vm.stopPrank();
    }

    function _assertRecoveryOutcome(RecoveryMarketSnapshot[] memory beforeState) private view {
        for (uint256 i; i < mintMarkets.length; ++i) {
            address marketAddress = mintMarkets[i];
            IMarket market = IMarket(marketAddress);
            Balance memory supply = market.totalSupply();
            (uint256 minted, uint256 ceiling) = dusd.minterConfig(marketAddress);
            AltoLeverage leverage = AltoLeverage(manifest.markets[i].leverage);

            assertEq(supply.assets, beforeState[i].badDebtAssets, "wrong recovered debt ceiling");
            assertEq(supply.shares, 0, "recovered supply shares remain");
            assertEq(minted, beforeState[i].mintedAssets, "recovered DUSD residual changed");
            assertEq(ceiling, 0, "recovered DUSD ceiling remains");
            assertFalse(dusd.allowedMinter(marketAddress), "recovered minter remains enabled");
            assertFalse(dusd.allowedBurner(marketAddress), "recovered burner remains enabled");
            assertFalse(marketRegistry.isMintMarket(marketAddress), "market remains registered");
            assertFalse(leverage.supportedMarkets(marketAddress), "leverage support remains");
            assertFalse(market.authorizedCallbacks(address(leverage)), "leverage callback remains");
            assertFalse(leverage.swapper().isWhitelisted(address(leverage)), "swapper permission remains");
            assertFalse(
                ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(marketAddress),
                "periphery support remains"
            );
            assertFalse(market.authorizedLiquidationPeriphery(liquidationPeriphery), "periphery authorization remains");
            assertTrue(altoAdapter.isApprovedContract(marketAddress), "AltoAdapter approval removed");
            assertEq(market.oracle(), beforeState[i].oracle, "oracle changed");
            _assertFrozenAndUnpaused(market);
        }
    }

    function _snapshotRecoveryState() private view returns (RecoveryMarketSnapshot[] memory snapshots) {
        snapshots = new RecoveryMarketSnapshot[](mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            address oracle = IMarket(mintMarkets[i]).oracle();
            (uint256 mintedAssets,) = dusd.minterConfig(mintMarkets[i]);
            snapshots[i] = RecoveryMarketSnapshot({
                oracle: oracle,
                badDebtAssets: AltoMintMarket(mintMarkets[i]).badDebtAssets(),
                mintedAssets: mintedAssets
            });
            assertNotEq(oracle, address(0), "test requires market oracle");
            assertTrue(altoAdapter.isApprovedContract(mintMarkets[i]), "test requires AltoAdapter approval");
        }
    }

    function _exerciseRetainedAdapterWithdrawal(uint256 marketIndex, uint256 oraclePrice) private {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        address borrower = _seededBorrower(marketIndex);
        Position memory positionBefore = market.position(borrower);
        assertEq(positionBefore.borrowShares, 0, "legacy borrower debt remains");
        assertGt(positionBefore.collateralAssets, 0, "legacy borrower has no collateral");
        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(oraclePrice));

        IERC20 collateralToken = IERC20(market.collateralToken());
        uint256 balanceBefore = collateralToken.balanceOf(borrower);
        vm.prank(borrower);
        IAuth(address(market)).setAuthorization(address(altoAdapter), true);

        Call[] memory bundle = new Call[](1);
        bundle[0] = Call({
            to: address(altoAdapter),
            data: abi.encodeCall(
                AltoAdapter.marketRemoveCollateral, (market, positionBefore.collateralAssets, borrower, bytes(""))
            ),
            value: 0,
            skipRevert: false,
            callbackHash: bytes32(0)
        });
        address bundler = altoAdapter.BUNDLER3();
        vm.prank(borrower);
        Bundler3(payable(bundler)).multicall(bundle);

        assertEq(market.position(borrower).collateralAssets, 0, "legacy collateral remains");
        assertEq(
            collateralToken.balanceOf(borrower) - balanceBefore,
            positionBefore.collateralAssets,
            "wrong legacy collateral withdrawal"
        );
        assertTrue(altoAdapter.isApprovedContract(address(market)), "adapter approval changed during withdrawal");
        _assertFrozenAndUnpaused(market);
    }
}
