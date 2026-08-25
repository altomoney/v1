// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {BatchAScript, BatchAConfig} from "../scripts/BatchA.s.sol";
import {BatchBScript, BatchBConfig, OffboardSeverity} from "../scripts/BatchB.s.sol";
import {BatchCScript, BatchCConfig} from "../scripts/BatchC.s.sol";

import {AltoVault} from "@alto/lending/vault/AltoVault.sol";
import {
    IMarket,
    Balance,
    Position,
    BaseMarketInitParams,
    BorrowMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVaultStaticTypes, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {IrmMock} from "@alto-test/helpers/IrmMock.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";

contract ErpOffboard02ResponsePathTest is Test {
    string internal constant OUTPUT = "ERP/ERP-OFFBOARD-02/output/";

    uint256 internal constant GOVERNANCE_DELAY = 2 days;
    uint256 internal constant VAULT_DELAY = 1 days;
    uint256 internal constant MEDIUM_NOTICE = 7 days;

    uint256 internal constant INITIAL_MARKET_LTV = 0.8 ether;
    uint256 internal constant INITIAL_LIQUIDATION_LTV = 0.85 ether;
    uint256 internal constant INITIAL_COMPLETE_LIQUIDATION_LTV = 0.9 ether;
    uint256 internal constant FIVE_PERCENTAGE_POINTS = 0.05 ether;

    address internal freezerSafe = makeAddr("Freezer Safe");
    address internal vaultSafe = makeAddr("Vault Safe");
    address internal timelockSafe = makeAddr("Timelock Safe");
    address internal supplier = makeAddr("Supplier");
    address internal borrower = makeAddr("Borrower");
    address internal feeRecipient = makeAddr("Fee Recipient");

    AltoTimelockController internal timelock;
    MarketRegistry internal marketRegistry;
    AltoAdapter internal adapter;
    AltoVault internal vault;
    DlbDcfPriorityLiquidationEngine internal liquidationEngine;
    FixedRateIrm internal fixedRateIrm;
    IMarket internal market;

    ERC20MockMintable internal loanToken;
    ERC20MockMintable internal collateralToken;

    BatchAScript internal batchA;
    BatchBScript internal batchB;
    BatchCScript internal batchC;

    function setUp() public {
        vm.warp(1_800_000_000);
        _deployGovernance();
        _deployRepresentativeMarket();
        _deployIntegrations();
        _seedOrdinaryUserPositions();

        batchA = new BatchAScript();
        batchB = new BatchBScript();
        batchC = new BatchCScript();
    }

    /// @dev Full response-path test. No bad state, storage mutation, or exceptional-loss path is injected.
    function testResponsePath_BatchesABC_ExecuteGeneratedSafeJson() public {
        uint256 responseStartedAt = block.timestamp;

        _generateAndExecuteBatchA();
        _assertBatchAState();

        uint256 t0 = responseStartedAt + MEDIUM_NOTICE;
        _generateAndScheduleBatchB();
        _assertCannotExecuteBeforeTimelock("batch-b-t0-execute.json");

        vm.warp(t0);
        _executeSafeJson("batch-b-t0-execute.json", timelockSafe);
        assertEq(market.irm(), address(fixedRateIrm), "dedicated IRM was not attached");
        assertEq(fixedRateIrm.market(), address(market), "dedicated IRM bound to wrong market");

        LiquidationConfiguration memory originalConfiguration =
            IDcfDlbPriorityLiquidationEngine(address(liquidationEngine)).liquidationConfiguration();
        _executeMediumCorrectionSchedule(t0);
        _assertUnscheduledLiquidationFieldsUnchanged(originalConfiguration);

        _exerciseFrozenMarketExitRoutes();
        _generateAndExecuteBatchC();
        _assertFinalState();
    }

    function testBatchBSchedulesMatchSection4() public view {
        assertEq(batchB.stepCount(OffboardSeverity.MEDIUM), 4);
        assertEq(batchB.stepOffset(OffboardSeverity.MEDIUM, 0), 1 days);
        assertEq(batchB.stepOffset(OffboardSeverity.MEDIUM, 1), 7 days);
        assertEq(batchB.stepOffset(OffboardSeverity.MEDIUM, 2), 14 days);
        assertEq(batchB.stepOffset(OffboardSeverity.MEDIUM, 3), 21 days);

        assertEq(batchB.stepCount(OffboardSeverity.HIGH), 4);
        assertEq(batchB.stepOffset(OffboardSeverity.HIGH, 0), 1 days);
        assertEq(batchB.stepOffset(OffboardSeverity.HIGH, 1), 4 days);
        assertEq(batchB.stepOffset(OffboardSeverity.HIGH, 2), 7 days);
        assertEq(batchB.stepOffset(OffboardSeverity.HIGH, 3), 10 days);

        assertEq(batchB.stepCount(OffboardSeverity.CRITICAL), 6);
        for (uint256 i; i < 6; ++i) {
            assertEq(batchB.stepOffset(OffboardSeverity.CRITICAL, i), (i + 1) * 1 days);
        }

        assertEq(batchB.stepRate(OffboardSeverity.MEDIUM, 0), batchB.aprToSpy(0.1 ether));
        assertEq(batchB.stepRate(OffboardSeverity.MEDIUM, 1), batchB.aprToSpy(0.2 ether));
        assertEq(batchB.stepRate(OffboardSeverity.MEDIUM, 2), batchB.aprToSpy(0.4 ether));
        assertEq(batchB.stepRate(OffboardSeverity.MEDIUM, 3), batchB.aprToSpy(0.8 ether));
        assertEq(batchB.stepRate(OffboardSeverity.CRITICAL, 4), batchB.aprToSpy(1.6 ether));
        assertEq(batchB.stepRate(OffboardSeverity.CRITICAL, 5), batchB.aprToSpy(3.2 ether));
    }

    function _deployGovernance() private {
        address[] memory proposers = new address[](1);
        proposers[0] = timelockSafe;
        address[] memory executors = new address[](1);
        executors[0] = timelockSafe;
        timelock = new AltoTimelockController(GOVERNANCE_DELAY, proposers, executors, timelockSafe);
    }

    function _deployRepresentativeMarket() private {
        loanToken = new ERC20MockMintable("Borrow Token", "BRW");
        collateralToken = new ERC20MockMintable("Collateral Token", "COL");

        OracleMock oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        IrmMock oldIrm = new IrmMock();
        oldIrm.setBorrowRate(0.05 ether / uint256(365 days));

        liquidationEngine = new DlbDcfPriorityLiquidationEngine(timelockSafe);
        BorrowMarketInitParams memory params = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(loanToken),
                collateralToken: address(collateralToken),
                irm: address(oldIrm),
                owner: freezerSafe,
                oracle: address(oracle),
                maxLtv: INITIAL_MARKET_LTV,
                feeRecipient: feeRecipient,
                liquidationEngine: address(liquidationEngine)
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: type(uint128).max,
            initialInterestFee: 0
        });
        market = IMarket(MarketDeployer.deployBorrowMarket(params));

        vm.prank(timelockSafe);
        liquidationEngine.setLiquidationConfiguration(_initialLiquidationConfiguration());
        vm.prank(freezerSafe);
        AltoOwnable2Step(address(market)).transferOwnershipSkip2Step(address(timelock));
        vm.prank(timelockSafe);
        liquidationEngine.transferOwnershipSkip2Step(address(timelock));

        fixedRateIrm = new FixedRateIrm(0.1 ether / uint256(365 days), address(timelock));
    }

    function _deployIntegrations() private {
        marketRegistry = new MarketRegistry(timelockSafe);
        adapter = new AltoAdapter(makeAddr("Bundler"), makeAddr("Wrapped Native"), timelockSafe);

        vm.startPrank(timelockSafe);
        marketRegistry.addBorrowMarket(address(market));
        adapter.approveContract(address(market));
        vm.stopPrank();

        vault = new AltoVault(
            vaultSafe, VAULT_DELAY, address(loanToken), "Representative Alto Vault", "rALTO", address(marketRegistry)
        );

        vm.startPrank(vaultSafe);
        vault.setCurator(vaultSafe);
        vault.setIsAllocator(vaultSafe, true);
        vault.submitCap(address(market), 2_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + VAULT_DELAY);
        vault.acceptCap(address(market));

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = address(market);
        vm.prank(vaultSafe);
        vault.setSupplyQueue(supplyQueue);

        vm.startPrank(timelockSafe);
        marketRegistry.transferOwnershipSkip2Step(address(timelock));
        adapter.transferOwnershipSkip2Step(address(timelock));
        vm.stopPrank();
    }

    function _seedOrdinaryUserPositions() private {
        loanToken.mint(supplier, 1_000 ether);
        loanToken.mint(borrower, 100 ether);
        collateralToken.mint(borrower, 100 ether);

        vm.startPrank(supplier);
        loanToken.approve(address(market), type(uint256).max);
        market.addSupply(1_000 ether, 0, supplier);
        vm.stopPrank();

        vm.startPrank(borrower);
        loanToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(100 ether, borrower);
        market.borrow(10 ether, 0, borrower, borrower, "");
        vm.stopPrank();
    }

    function _generateAndExecuteBatchA() private {
        address[] memory supplyQueueAfter = new address[](0);
        MarketAllocation[] memory reallocations = new MarketAllocation[](1);
        reallocations[0] = MarketAllocation({market: address(market), assets: 0});

        batchA.write(
            BatchAConfig({
                freezerSafe: freezerSafe,
                vaultSafe: vaultSafe,
                market: address(market),
                vault: address(vault),
                supplyQueueAfter: supplyQueueAfter,
                reallocations: reallocations
            })
        );
        _executeSafeJson("batch-a-freeze-safe.json", freezerSafe);
        _executeSafeJson("batch-a-vault-safe.json", vaultSafe);
    }

    function _assertBatchAState() private {
        assertTrue(market.paused(FROZEN_TYPE), "market is not frozen");
        assertFalse(market.paused(PAUSE_TYPE), "market is paused");

        (uint184 cap, bool enabled, uint64 removableAt) = IAltoVaultStaticTypes(address(vault)).config(address(market));
        assertEq(cap, 0, "vault cap is not zero");
        assertTrue(enabled, "vault market disabled too early");
        assertEq(removableAt, 0, "ordinary removal was submitted");
        assertEq(vault.supplyQueueLength(), 0, "market remains in supply queue");
        assertEq(vault.withdrawQueueLength(), 1, "withdraw route was removed");
        assertEq(vault.withdrawQueue(0), address(market), "wrong withdraw route");
        assertTrue(marketRegistry.isBorrowMarket(address(market)), "registry removal happened in Batch A");
        assertTrue(adapter.isApprovedContract(address(market)), "adapter exit route removed in Batch A");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        vm.prank(supplier);
        market.addSupply(1 ether, 0, supplier);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        vm.prank(borrower);
        market.addCollateral(1 ether, borrower);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        vm.prank(borrower);
        market.borrow(1 ether, 0, borrower, borrower, "");
    }

    function _generateAndScheduleBatchB() private {
        uint256 count = batchB.stepCount(OffboardSeverity.MEDIUM);
        uint256[] memory rates = new uint256[](count);
        uint256[] memory marketLtvs = new uint256[](count);
        uint256[] memory liquidationLtvs = new uint256[](count);
        uint256[] memory completeLtvs = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            rates[i] = batchB.stepRate(OffboardSeverity.MEDIUM, i);
            marketLtvs[i] = INITIAL_MARKET_LTV - (i + 1) * FIVE_PERCENTAGE_POINTS;
            liquidationLtvs[i] = INITIAL_LIQUIDATION_LTV - (i + 1) * FIVE_PERCENTAGE_POINTS;
            completeLtvs[i] = INITIAL_COMPLETE_LIQUIDATION_LTV - (i + 1) * FIVE_PERCENTAGE_POINTS;
        }

        batchB.write(
            BatchBConfig({
                timelockSafe: timelockSafe,
                timelock: address(timelock),
                market: address(market),
                liquidationEngine: address(liquidationEngine),
                fixedRateIrm: address(fixedRateIrm),
                governanceDelay: GOVERNANCE_DELAY,
                severity: OffboardSeverity.MEDIUM,
                initialRate: batchB.aprToSpy(0.1 ether),
                stepRates: rates,
                marketMaxLtvs: marketLtvs,
                maxLiquidationLtvs: liquidationLtvs,
                completeLiquidationLtvs: completeLtvs
            })
        );

        _executeSafeJson("batch-b-t0-schedule.json", timelockSafe);
        for (uint256 i; i < batchB.stepCount(OffboardSeverity.MEDIUM); ++i) {
            _executeSafeJson(string.concat("batch-b-step-", vm.toString(i + 1), "-schedule.json"), timelockSafe);
        }
    }

    function _executeMediumCorrectionSchedule(uint256 t0) private {
        uint256 expectedMarketLtv = INITIAL_MARKET_LTV;
        uint256 expectedLiquidationLtv = INITIAL_LIQUIDATION_LTV;
        uint256 expectedCompleteLtv = INITIAL_COMPLETE_LIQUIDATION_LTV;

        for (uint256 i; i < batchB.stepCount(OffboardSeverity.MEDIUM); ++i) {
            vm.warp(t0 + batchB.stepOffset(OffboardSeverity.MEDIUM, i));
            _executeSafeJson(string.concat("batch-b-step-", vm.toString(i + 1), "-execute.json"), timelockSafe);

            expectedMarketLtv -= FIVE_PERCENTAGE_POINTS;
            expectedLiquidationLtv -= FIVE_PERCENTAGE_POINTS;
            expectedCompleteLtv -= FIVE_PERCENTAGE_POINTS;
            LiquidationConfiguration memory current =
                IDcfDlbPriorityLiquidationEngine(address(liquidationEngine)).liquidationConfiguration();

            (uint256 borrowRate,) = fixedRateIrm.irState();

            assertEq(borrowRate, batchB.stepRate(OffboardSeverity.MEDIUM, i));
            assertEq(market.maxLtv(), expectedMarketLtv, "wrong market LTV");
            assertEq(current.maxLiquidationLtv, expectedLiquidationLtv, "wrong liquidation LTV");
            assertEq(current.ltvForCompleteLiquidation, expectedCompleteLtv, "wrong complete LTV");
            assertLe(market.maxLtv(), current.maxLiquidationLtv, "market/engine LTV order");
            assertLe(current.maxLiquidationLtv, current.ltvForCompleteLiquidation, "engine LTV order");
            assertTrue(market.paused(FROZEN_TYPE), "freeze lost during Batch B");
            assertFalse(market.paused(PAUSE_TYPE), "pause introduced during Batch B");
        }
    }

    function _exerciseFrozenMarketExitRoutes() private {
        Position memory borrowerPosition = market.position(borrower);
        vm.startPrank(borrower);
        market.repay(0, borrowerPosition.borrowShares, borrower);
        market.removeCollateral(borrowerPosition.collateralAssets, borrower, borrower, "");
        vm.stopPrank();

        Position memory supplierPosition = market.position(supplier);
        vm.prank(supplier);
        market.removeSupply(0, supplierPosition.supplyShares, supplier, supplier);

        Balance memory borrowed = market.totalBorrowed();
        assertEq(borrowed.assets, 0, "borrow assets remain");
        assertEq(borrowed.shares, 0, "borrow shares remain");
        assertEq(market.position(supplier).supplyShares, 0, "supplier position remains");
        assertEq(market.position(borrower).collateralAssets, 0, "borrower collateral remains");
    }

    function _generateAndExecuteBatchC() private {
        uint256[] memory withdrawQueueIndexesAfter = new uint256[](0);
        batchC.write(
            BatchCConfig({
                vaultSafe: vaultSafe,
                timelockSafe: timelockSafe,
                timelock: address(timelock),
                market: address(market),
                vault: address(vault),
                marketRegistry: address(marketRegistry),
                adapter: address(adapter),
                governanceDelay: GOVERNANCE_DELAY,
                withdrawQueueIndexesAfter: withdrawQueueIndexesAfter
            })
        );

        _executeSafeJson("batch-c-vault-safe.json", vaultSafe);
        _executeSafeJson("batch-c-final-removal-schedule.json", timelockSafe);
        _assertCannotExecuteBeforeTimelock("batch-c-final-removal-execute.json");
        vm.warp(block.timestamp + GOVERNANCE_DELAY);
        _executeSafeJson("batch-c-final-removal-execute.json", timelockSafe);
    }

    function _assertFinalState() private view {
        (uint184 cap, bool enabled,) = IAltoVaultStaticTypes(address(vault)).config(address(market));
        assertEq(cap, 0, "final vault cap");
        assertFalse(enabled, "final vault config enabled");
        assertEq(vault.supplyQueueLength(), 0, "final supply queue");
        assertEq(vault.withdrawQueueLength(), 0, "final withdraw queue");
        assertEq(vault.quarantinedAssets(address(market)), 0, "ordinary removal quarantined assets");
        assertFalse(marketRegistry.isBorrowMarket(address(market)), "market remains registered");
        assertFalse(adapter.isApprovedContract(address(market)), "market remains adapter-approved");
        assertTrue(market.paused(FROZEN_TYPE), "market is not frozen at close");
        assertFalse(market.paused(PAUSE_TYPE), "market is paused at close");
    }

    function _assertCannotExecuteBeforeTimelock(string memory fileName) private {
        string memory json = vm.readFile(string.concat(OUTPUT, fileName));
        address target = vm.parseJsonAddress(json, ".transactions[0].to");
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), timelockSafe, "wrong Timelock Safe");
        vm.prank(timelockSafe);
        (bool success,) = target.call(data);
        assertFalse(success, "Timelock executed before its delay");
    }

    function _executeSafeJson(string memory fileName, address expectedSafe) private {
        string memory json = vm.readFile(string.concat(OUTPUT, fileName));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), expectedSafe, "wrong Safe route");

        uint256 i;
        while (vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]"))) {
            string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
            assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "non-zero Safe value");

            vm.prank(expectedSafe);
            (bool success, bytes memory returnData) = target.call(data);
            if (!success) _bubbleRevert(returnData);
            ++i;
        }
        assertGt(i, 0, "empty Safe JSON");
    }

    function _assertUnscheduledLiquidationFieldsUnchanged(LiquidationConfiguration memory before_) private view {
        LiquidationConfiguration memory after_ =
            IDcfDlbPriorityLiquidationEngine(address(liquidationEngine)).liquidationConfiguration();
        assertEq(after_.dynamicBonusFeeStart, before_.dynamicBonusFeeStart);
        assertEq(after_.dynamicBonusFeeDecaySteepness, before_.dynamicBonusFeeDecaySteepness);
        assertEq(after_.liquidationBaseFee, before_.liquidationBaseFee);
        assertEq(after_.minPenaltyPercentage, before_.minPenaltyPercentage);
        assertEq(after_.protocolFeePercentage, before_.protocolFeePercentage);
        assertEq(after_.isEnabledPriorityLiquidation, before_.isEnabledPriorityLiquidation);
        assertEq(after_.disablePriorityLiquidationAbovePositionLtv, before_.disablePriorityLiquidationAbovePositionLtv);
        assertEq(after_.priorityLiquidationGracePeriod, before_.priorityLiquidationGracePeriod);
        assertEq(after_.taggerLiquidationGracePeriod, before_.taggerLiquidationGracePeriod);
        assertEq(after_.liquidationWindowTag, before_.liquidationWindowTag);
    }

    function _initialLiquidationConfiguration() private pure returns (LiquidationConfiguration memory) {
        return LiquidationConfiguration({
            maxLiquidationLtv: INITIAL_LIQUIDATION_LTV,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: INITIAL_COMPLETE_LIQUIDATION_LTV,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.07 ether,
            minPenaltyPercentage: 0.005 ether,
            protocolFeePercentage: 0.07 ether,
            isEnabledPriorityLiquidation: false,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 1 hours,
            taggerLiquidationGracePeriod: 30 minutes,
            liquidationWindowTag: 3 days
        });
    }

    function _bubbleRevert(bytes memory returnData) private pure {
        if (returnData.length == 0) revert("Safe transaction failed");
        assembly ("memory-safe") {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }
}
