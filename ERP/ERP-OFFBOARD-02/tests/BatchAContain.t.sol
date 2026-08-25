// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboardingPhase} from "../IBorrowMarketOffboarding.sol";

import {MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchAContainTest is BorrowMarketOffboardingTestBase {
    function setUp() public {
        _setUpManifest();
        if (marketAlreadyFrozen) return;

        _seedStandardPositions();
        _assertAllRequiredExitIntegrationsActive();
    }

    function testBatchAFreezesMarketsAndPreservesExitAndLiquidationRoutes() public {
        if (marketAlreadyFrozen) return;

        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, input);
        _executeFreezeBatch();
        _executeCuratorBatch();
        _executeAllocatorActions();
        _assertContainmentAndRoutes();
    }

    function testBatchARevokesPendingCapsBeforeSettingCapsToZero() public {
        if (marketAlreadyFrozen) return;

        address curator = vault.curator();
        for (uint256 i; i < 2; ++i) {
            address market = borrowMarkets[i];
            if (vault.pendingCap(market).validAt != 0) {
                vm.prank(curator);
                vault.revokePendingCap(market);
            }

            uint256 pendingCap = uint256(vault.config(market).cap) + 1;
            vm.prank(curator);
            vault.submitCap(market, pendingCap);
            assertGt(vault.pendingCap(market).validAt, 0, "pending cap not created");
        }

        uint256 pendingCapCount = _pendingCapCount();
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, input);
        _executeFreezeBatch();
        uint256 curatorTransactionCount = _executeCuratorBatch();
        _executeAllocatorActions();

        assertEq(
            curatorTransactionCount,
            borrowMarkets.length + pendingCapCount,
            "wrong revoke and zero-cap transaction count"
        );
        _assertContainmentAndRoutes();
    }

    function _assertContainmentAndRoutes() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketContainmentAndRoutes(i);
        }
    }

    function _assertMarketContainmentAndRoutes(uint256 marketIndex) internal {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        MarketFixture memory fixture = fixtures[marketIndex];

        _assertFrozenAndUnpaused(market);
        _assertVaultContained(address(market));
        _assertRequiredExitIntegrationsActive(marketIndex);
        _assertEntrancesBlocked(market, fixture.exitBorrower);
        _exerciseBatchAExitRoutes(market, fixture);
        _exerciseBatchALiquidation(market, fixture);
        _assertFrozenAndUnpaused(market);
        _assertRequiredExitIntegrationsActive(marketIndex);
    }

    function _executeFreezeBatch() private {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, FREEZE_FILE));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), FREEZER_SAFE, "wrong Freezer Safe");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            (address target, bytes memory data) = _jsonTransaction(json, i);
            assertEq(target, borrowMarkets[i], "wrong freeze target or order");
            assertEq(data, abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true)), "wrong freeze calldata");
            _callFrom(FREEZER_SAFE, target, data);
        }
        assertFalse(_jsonTransactionExists(json, borrowMarkets.length), "unexpected freeze transaction");
    }

    function _executeCuratorBatch() private returns (uint256 transactionCount) {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, CURATOR_FILE));
        address curator = vault.curator();
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), curator, "wrong curator Safe");

        while (_jsonTransactionExists(json, transactionCount)) {
            (address target, bytes memory data) = _jsonTransaction(json, transactionCount);
            assertEq(target, address(vault), "wrong Vault target");
            _callFrom(curator, target, data);
            ++transactionCount;
        }
        assertGe(transactionCount, borrowMarkets.length, "missing zero-cap transactions");
        assertLe(transactionCount, borrowMarkets.length * 2, "unexpected curator transactions");
    }

    function _executeAllocatorActions() private {
        assertTrue(vault.isAllocator(VAULT_ALLOCATOR), "configured allocator is not authorized");

        uint256[] memory vaultSupplySharesBefore = new uint256[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            vaultSupplySharesBefore[i] = IMarket(borrowMarkets[i]).position(address(vault)).supplyShares;
        }

        address[] memory remainingSupplyQueue = _supplyQueueWithoutAffectedMarkets();
        assertEq(remainingSupplyQueue.length, 0, "current manifest has an unexpected reallocation destination");

        vm.prank(VAULT_ALLOCATOR);
        vault.setSupplyQueue(remainingSupplyQueue);

        MarketAllocation[] memory allocations = new MarketAllocation[](0);
        vm.prank(VAULT_ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(vault.supplyQueueLength(), 0, "affected markets remain in the supply queue");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertEq(
                IMarket(borrowMarkets[i]).position(address(vault)).supplyShares,
                vaultSupplySharesBefore[i],
                "zero-reallocation changed Vault exposure"
            );
        }
    }

    function _supplyQueueWithoutAffectedMarkets() private view returns (address[] memory remainingQueue) {
        uint256 queueLength = vault.supplyQueueLength();
        uint256 remainingCount;
        for (uint256 i; i < queueLength; ++i) {
            if (!_isAffectedMarket(vault.supplyQueue(i))) ++remainingCount;
        }

        remainingQueue = new address[](remainingCount);
        uint256 nextIndex;
        for (uint256 i; i < queueLength; ++i) {
            address market = vault.supplyQueue(i);
            if (!_isAffectedMarket(market)) {
                remainingQueue[nextIndex] = market;
                ++nextIndex;
            }
        }
    }

    function _pendingCapCount() private view returns (uint256 count) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            if (vault.pendingCap(borrowMarkets[i]).validAt != 0) ++count;
        }
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

    function _exerciseBatchAExitRoutes(IMarket market, MarketFixture memory fixture) private {
        Position memory supplyPosition = market.position(fixture.supplier);
        Position memory borrowPosition = market.position(fixture.exitBorrower);
        IERC20 borrowToken = IERC20(market.borrowToken());

        deal(address(borrowToken), fixture.exitBorrower, 1_000_000 ether);
        vm.startPrank(fixture.exitBorrower);
        borrowToken.approve(address(market), type(uint256).max);
        market.repay(0, borrowPosition.borrowShares, fixture.exitBorrower);
        market.removeCollateral(borrowPosition.collateralAssets, fixture.exitBorrower, fixture.exitBorrower, "");
        vm.stopPrank();

        vm.prank(fixture.supplier);
        (uint256 withdrawnAssets,) =
            market.removeSupply(0, supplyPosition.supplyShares, fixture.supplier, fixture.supplier);

        assertGt(withdrawnAssets, 0, "removeSupply returned no assets");
        assertEq(market.position(fixture.supplier).supplyShares, 0, "removeSupply route failed");
        assertEq(market.position(fixture.exitBorrower).borrowShares, 0, "repay route failed");
        assertEq(market.position(fixture.exitBorrower).collateralAssets, 0, "removeCollateral route failed");
    }

    function _exerciseBatchALiquidation(IMarket market, MarketFixture memory fixture) private {
        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(fixture.livePrice / 4));

        Position memory positionBefore = market.position(fixture.liquidationBorrower);
        IERC20 borrowToken = IERC20(market.borrowToken());
        deal(address(borrowToken), fixture.liquidator, 1_000_000 ether);

        vm.startPrank(fixture.liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (uint256 seizedCollateral, uint256 repaidBorrow,) = market.liquidate(fixture.liquidationBorrower, "", "");
        vm.stopPrank();

        Position memory positionAfter = market.position(fixture.liquidationBorrower);
        assertGt(seizedCollateral, 0, "liquidation seized no collateral");
        assertGt(repaidBorrow, 0, "liquidation repaid no debt");
        assertLt(positionAfter.borrowShares, positionBefore.borrowShares, "liquidation did not reduce debt");
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "liquidation seized no position");
    }

    function _assertVaultContained(address market) private view {
        MarketConfig memory config = vault.config(market);
        PendingUint192 memory pendingCap = vault.pendingCap(market);
        Position memory vaultPosition = IMarket(market).position(address(vault));

        assertEq(config.cap, 0, "Vault cap not zero");
        assertEq(pendingCap.validAt, 0, "Vault pending cap remains");
        assertFalse(_isInSupplyQueue(market), "market remains in Vault supply queue");
        if (vaultPosition.supplyShares != 0) {
            assertTrue(_isInWithdrawQueue(market), "market with Vault supply absent from withdrawal queue");
        }
    }
}
