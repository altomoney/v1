// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {BatchBFixedRateIrmScript} from "../../scripts/BatchB.s.sol";
import {BatchBLtvReductionScript} from "../../scripts/BatchBLtvReduction.s.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {IAltoVault} from "@alto/lending/interfaces/IAltoVault.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

struct BatchBMarketSnapshot {
    address market;
    address irm;
    address liquidationEngine;
    uint256 maxLtv;
    LiquidationConfiguration liquidationConfiguration;
}

contract BatchBLiveTest is Test {
    string internal constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    string internal constant OUTPUT_DIRECTORY = "ERP/ERP-OFFBOARD-02/output/";

    address internal constant PRODUCTION_TIMELOCK_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address internal constant PRODUCTION_FREEZER = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;
    address internal constant VAULT_SHARE_HOLDER = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    BatchBFixedRateIrmScript internal fixedRateIrmScript;
    BatchBLtvReductionScript internal irmAndLtvScript;
    OwnerFixedRateIrmFactory internal factory;
    TimelockController internal timelock;
    IAltoVault internal vault;

    address[] internal borrowMarkets;
    uint256[] internal initialRatesSpy;
    uint256[] internal correctionRatesSpy;

    address internal exitBorrower;
    address internal liquidationBorrower;
    address internal liquidator;
    uint256 internal representativePrice;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        timelock = TimelockController(payable(vm.parseJsonAddress(addresses, ".contracts.timelock")));
        vault = IAltoVault(vm.parseJsonAddress(addresses, ".contracts.dusdVault"));

        fixedRateIrmScript = new BatchBFixedRateIrmScript();
        irmAndLtvScript = new BatchBLtvReductionScript();
        factory = new OwnerFixedRateIrmFactory(address(timelock));
        fixedRateIrmScript.setOwnerFixedRateIrmFactory(address(factory));

        (borrowMarkets, initialRatesSpy) = fixedRateIrmScript.borrowMarketConfiguration();
        (address[] memory correctionMarkets, uint256[] memory configuredCorrectionRates) =
            irmAndLtvScript.borrowMarketConfiguration();
        correctionRatesSpy = configuredCorrectionRates;

        assertEq(correctionMarkets, borrowMarkets, "Batch B scripts use different markets");
        assertEq(initialRatesSpy.length, borrowMarkets.length, "initial rate length");
        assertEq(correctionRatesSpy.length, borrowMarkets.length, "correction rate length");

        exitBorrower = makeAddr("Batch B exit borrower");
        liquidationBorrower = makeAddr("Batch B liquidation borrower");
        liquidator = makeAddr("Batch B liquidator");
    }

    function testLiveBatchBRequiresConfiguredFactory() public {
        BatchBFixedRateIrmScript unsetScript = new BatchBFixedRateIrmScript();

        vm.expectRevert("Batch B: zero factory");
        unsetScript.setOwnerFixedRateIrmFactory(address(0));

        vm.expectRevert("Batch B: set factory address");
        unsetScript.run();
    }

    function testLiveBatchBStopsBeforeContainment() public {
        assertFalse(IMarketBase(borrowMarkets[0]).paused(FROZEN_TYPE), "live market already frozen");
        vm.expectRevert("Batch B: market not frozen");
        fixedRateIrmScript.run();
    }

    function testLiveBatchBExecutesBothGeneratedTimelockBatches() public {
        _seedRepresentativePositions();
        _freezeBorrowMarkets();

        uint256 initialNonce = factory.nonce();
        address[] memory predictedIrms = _predictedIrms(initialNonce);
        BatchBMarketSnapshot[] memory beforeAttachment = _marketSnapshots();

        fixedRateIrmScript.run();
        _assertFixedRateIrmJson(predictedIrms);

        uint256 governanceDelay = timelock.getMinDelay();
        _scheduleAndExecute("batch-b-fixed-rate-irm", governanceDelay);
        _assertFixedRateIrmAttachment(beforeAttachment, predictedIrms);

        BatchBMarketSnapshot[] memory beforeCorrection = _marketSnapshots();
        irmAndLtvScript.run();
        _assertIrmAndLtvJson(beforeCorrection);

        uint256 correctionDelay = governanceDelay > 1 hours ? governanceDelay : 1 hours;
        assertGe(correctionDelay, 1 hours, "terminal correction delay below one hour");
        _scheduleAndExecute("batch-b-irm-and-ltv-update", correctionDelay);
        _assertIrmAndLtvState(beforeCorrection);

        _retainLivePriceAcrossSimulatedDelays();
        _exerciseRepaymentAndCollateralWithdrawal();
        _exercisePermissionlessLiquidation();
        _exerciseVaultWithdrawalWithoutLoss();
    }

    function testLiveBatchBLtvFlooring() public view {
        assertEq(irmAndLtvScript.reduceByFivePercentagePoints(0.8 ether), 0.75 ether);
        assertEq(irmAndLtvScript.reduceByFivePercentagePoints(0.05 ether), 0);
        assertEq(irmAndLtvScript.reduceByFivePercentagePoints(0.03 ether), 0);
        assertEq(irmAndLtvScript.reduceByFivePercentagePoints(0), 0);
    }

    function _seedRepresentativePositions() private {
        IMarket market = IMarket(borrowMarkets[0]);
        assertFalse(market.paused(FROZEN_TYPE), "representative market already frozen");
        assertFalse(market.paused(PAUSE_TYPE), "representative market paused");

        IERC20 collateralToken = IERC20(market.collateralToken());
        representativePrice = IOracle(market.oracle()).getPrice();

        uint256 exitCollateral = 100_000; // 0.001 WBTC.
        deal(address(collateralToken), exitBorrower, exitCollateral);
        vm.startPrank(exitBorrower);
        collateralToken.approve(address(market), exitCollateral);
        market.addCollateral(exitCollateral, exitBorrower);
        market.borrow(10 ether, 0, exitBorrower, exitBorrower, "");
        vm.stopPrank();

        uint256 liquidationCollateral = 1_000_000; // 0.01 WBTC.
        deal(address(collateralToken), liquidationBorrower, liquidationCollateral);
        vm.startPrank(liquidationBorrower);
        collateralToken.approve(address(market), liquidationCollateral);
        market.addCollateral(liquidationCollateral, liquidationBorrower);

        uint256 collateralValue =
            Math.mulDiv(liquidationCollateral, representativePrice, LENDING_ORACLE_PRICE_PRECISION);
        uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);
        // `borrow` adds the opening fee to the position debt. Seed the position just below max LTV so that the
        // Timelock delay and approved fixed rate carry it above the reduced liquidation threshold.
        uint256 targetDebt = maximumBorrow - 1e12;
        uint256 borrowAssets = Math.mulDiv(targetDebt, 1 ether, 1 ether + market.borrowOpeningFee()) - 1;
        market.borrow(borrowAssets, 0, liquidationBorrower, liquidationBorrower, "");
        vm.stopPrank();
    }

    function _retainLivePriceAcrossSimulatedDelays() private {
        // A static fork does not receive new Chainlink rounds while `vm.warp` advances the Timelock. Preserve the
        // price read from live state so route tests are not turned into an unintended stale-oracle failure test.
        address oracle = IMarketBase(borrowMarkets[0]).oracle();
        vm.mockCall(oracle, abi.encodeCall(IOracle.getPrice, ()), abi.encode(representativePrice));
    }

    function _freezeBorrowMarkets() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarketBase market = IMarketBase(borrowMarkets[i]);
            assertFalse(market.paused(PAUSE_TYPE), "market paused before Batch B");
            assertFalse(market.paused(FROZEN_TYPE), "market frozen before containment simulation");

            vm.prank(PRODUCTION_FREEZER);
            market.pause(FROZEN_TYPE, true);

            assertTrue(market.paused(FROZEN_TYPE), "market was not frozen");
            assertFalse(market.paused(PAUSE_TYPE), "market was paused");
        }
    }

    function _predictedIrms(uint256 initialNonce) private view returns (address[] memory predictedIrms) {
        predictedIrms = new address[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            predictedIrms[i] = factory.predictIrmAddress(initialRatesSpy[i], address(timelock), initialNonce + i);
        }
    }

    function _marketSnapshots() private view returns (BatchBMarketSnapshot[] memory snapshots) {
        snapshots = new BatchBMarketSnapshot[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarketBase market = IMarketBase(borrowMarkets[i]);
            address liquidationEngine = market.liquidationEngine();
            snapshots[i] = BatchBMarketSnapshot({
                market: address(market),
                irm: market.irm(),
                liquidationEngine: liquidationEngine,
                maxLtv: market.maxLtv(),
                liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration()
            });
        }
    }

    function _assertFixedRateIrmJson(address[] memory predictedIrms) private view {
        uint256 callCount = borrowMarkets.length * 2;
        address[] memory targets = new address[](callCount);
        bytes[] memory payloads = new bytes[](callCount);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            targets[i] = address(factory);
            payloads[i] = abi.encodeCall(
                OwnerFixedRateIrmFactory.deploy, (borrowMarkets[i], initialRatesSpy[i], address(timelock))
            );
            targets[borrowMarkets.length + i] = borrowMarkets[i];
            payloads[borrowMarkets.length + i] = abi.encodeCall(IMarketBase.setIrm, (predictedIrms[i], false));
        }

        _assertTimelockPairJson("batch-b-fixed-rate-irm", targets, payloads, timelock.getMinDelay(), bytes32(0));
    }

    function _assertIrmAndLtvJson(BatchBMarketSnapshot[] memory beforeCorrection) private view {
        uint256 callCount = borrowMarkets.length * 3;
        address[] memory targets = new address[](callCount);
        bytes[] memory payloads = new bytes[](callCount);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            LiquidationConfiguration memory beforeConfig = beforeCorrection[i].liquidationConfiguration;
            LiquidationConfiguration memory expectedConfig = LiquidationConfiguration({
                maxLiquidationLtv: irmAndLtvScript.reduceByFivePercentagePoints(beforeConfig.maxLiquidationLtv),
                dynamicBonusFeeStart: beforeConfig.dynamicBonusFeeStart,
                ltvForCompleteLiquidation: irmAndLtvScript.reduceByFivePercentagePoints(
                    beforeConfig.ltvForCompleteLiquidation
                ),
                dynamicBonusFeeDecaySteepness: beforeConfig.dynamicBonusFeeDecaySteepness,
                liquidationBaseFee: beforeConfig.liquidationBaseFee,
                minPenaltyPercentage: beforeConfig.minPenaltyPercentage,
                protocolFeePercentage: beforeConfig.protocolFeePercentage,
                isEnabledPriorityLiquidation: beforeConfig.isEnabledPriorityLiquidation,
                disablePriorityLiquidationAbovePositionLtv: beforeConfig.disablePriorityLiquidationAbovePositionLtv,
                priorityLiquidationGracePeriod: beforeConfig.priorityLiquidationGracePeriod,
                taggerLiquidationGracePeriod: beforeConfig.taggerLiquidationGracePeriod,
                liquidationWindowTag: beforeConfig.liquidationWindowTag
            });

            targets[i * 3] = beforeCorrection[i].irm;
            payloads[i * 3] = abi.encodeCall(FixedRateIrm.setBorrowRate, (correctionRatesSpy[i]));
            targets[i * 3 + 1] = borrowMarkets[i];
            payloads[i * 3 + 1] = abi.encodeCall(
                IMarketBase.setMaxLtv, (irmAndLtvScript.reduceByFivePercentagePoints(beforeCorrection[i].maxLtv))
            );
            targets[i * 3 + 2] = beforeCorrection[i].liquidationEngine;
            payloads[i * 3 + 2] =
                abi.encodeCall(IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (expectedConfig));
        }

        uint256 delay = timelock.getMinDelay() > 1 hours ? timelock.getMinDelay() : 1 hours;
        _assertTimelockPairJson("batch-b-irm-and-ltv-update", targets, payloads, delay, bytes32(0));
    }

    function _assertTimelockPairJson(
        string memory fileStem,
        address[] memory targets,
        bytes[] memory payloads,
        uint256 delay,
        bytes32 salt
    ) private view {
        uint256[] memory values = new uint256[](targets.length);
        bytes32 predecessor;

        bytes memory expectedSchedule =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory expectedExecute =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        _assertSingleTimelockJson(string.concat(fileStem, "-schedule.json"), expectedSchedule);
        _assertSingleTimelockJson(string.concat(fileStem, "-execute.json"), expectedExecute);
    }

    function _assertSingleTimelockJson(string memory fileName, bytes memory expectedData) private view {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, fileName));
        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(block.chainid), "wrong JSON chain");
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(timelock), "wrong Timelock target");
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "0", "non-zero Timelock value");
        assertEq(vm.parseJsonBytes(json, ".transactions[0].data"), expectedData, "wrong Timelock calldata");
        assertFalse(vm.keyExistsJson(json, ".transactions[1]"), "unexpected extra outer transaction");
    }

    function _scheduleAndExecute(string memory fileStem, uint256 delay) private {
        _callTimelockJson(string.concat(fileStem, "-schedule.json"));

        string memory executeJson = vm.readFile(string.concat(OUTPUT_DIRECTORY, fileStem, "-execute.json"));
        address target = vm.parseJsonAddress(executeJson, ".transactions[0].to");
        bytes memory data = vm.parseJsonBytes(executeJson, ".transactions[0].data");

        vm.prank(PRODUCTION_TIMELOCK_SAFE);
        (bool executedEarly,) = target.call(data);
        assertFalse(executedEarly, "Timelock batch executed before delay");

        vm.warp(block.timestamp + delay);
        _callTimelockJson(string.concat(fileStem, "-execute.json"));
    }

    function _callTimelockJson(string memory fileName) private {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, fileName));
        address target = vm.parseJsonAddress(json, ".transactions[0].to");
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");

        vm.prank(PRODUCTION_TIMELOCK_SAFE);
        (bool success, bytes memory returnData) = target.call(data);
        assertTrue(success, string(returnData));
    }

    function _assertFixedRateIrmAttachment(
        BatchBMarketSnapshot[] memory beforeAttachment,
        address[] memory predictedIrms
    ) private view {
        assertEq(factory.nonce(), borrowMarkets.length, "factory nonce");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarketBase market = IMarketBase(borrowMarkets[i]);
            assertNotEq(market.irm(), beforeAttachment[i].irm, "old IRM remains attached");
            assertEq(market.irm(), predictedIrms[i], "wrong fixed-rate IRM attached");
            assertEq(FixedRateIrm(predictedIrms[i]).market(), borrowMarkets[i], "IRM bound to wrong market");
            assertEq(FixedRateIrm(predictedIrms[i]).owner(), address(timelock), "wrong IRM owner");

            (uint256 borrowRate,) = FixedRateIrm(predictedIrms[i]).irState();
            assertEq(borrowRate, initialRatesSpy[i], "wrong initial fixed rate");
            _assertFrozenAndUnpaused(market);

            for (uint256 j; j < i; ++j) {
                assertNotEq(predictedIrms[i], predictedIrms[j], "IRM reused across markets");
            }
        }
    }

    function _assertIrmAndLtvState(BatchBMarketSnapshot[] memory beforeCorrection) private view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarketBase market = IMarketBase(borrowMarkets[i]);
            LiquidationConfiguration memory afterConfig =
                IDcfDlbPriorityLiquidationEngine(beforeCorrection[i].liquidationEngine).liquidationConfiguration();

            (uint256 borrowRate,) = FixedRateIrm(beforeCorrection[i].irm).irState();
            assertEq(borrowRate, correctionRatesSpy[i], "correction rate does not match schedule");

            uint256 expectedMarketLtv = irmAndLtvScript.reduceByFivePercentagePoints(beforeCorrection[i].maxLtv);
            uint256 expectedLiquidationLtv = irmAndLtvScript.reduceByFivePercentagePoints(
                beforeCorrection[i].liquidationConfiguration.maxLiquidationLtv
            );
            uint256 expectedCompleteLtv = irmAndLtvScript.reduceByFivePercentagePoints(
                beforeCorrection[i].liquidationConfiguration.ltvForCompleteLiquidation
            );

            assertEq(market.maxLtv(), expectedMarketLtv, "wrong market max LTV");
            assertEq(afterConfig.maxLiquidationLtv, expectedLiquidationLtv, "wrong liquidation max LTV");
            assertEq(afterConfig.ltvForCompleteLiquidation, expectedCompleteLtv, "wrong complete-liquidation LTV");
            assertLe(beforeCorrection[i].maxLtv - market.maxLtv(), 0.05 ether, "market LTV step too large");
            assertLe(
                beforeCorrection[i].liquidationConfiguration.maxLiquidationLtv - afterConfig.maxLiquidationLtv,
                0.05 ether,
                "liquidation LTV step too large"
            );
            assertLe(
                beforeCorrection[i].liquidationConfiguration.ltvForCompleteLiquidation
                    - afterConfig.ltvForCompleteLiquidation,
                0.05 ether,
                "complete-liquidation LTV step too large"
            );
            assertLe(market.maxLtv(), afterConfig.maxLiquidationLtv, "market/liquidation LTV order");
            assertLe(
                afterConfig.maxLiquidationLtv, afterConfig.ltvForCompleteLiquidation, "liquidation/complete LTV order"
            );

            _assertUnscheduledLiquidationFieldsUnchanged(beforeCorrection[i].liquidationConfiguration, afterConfig);
            _assertFrozenAndUnpaused(market);
        }
    }

    function _assertUnscheduledLiquidationFieldsUnchanged(
        LiquidationConfiguration memory beforeConfig,
        LiquidationConfiguration memory afterConfig
    ) private pure {
        assertEq(afterConfig.dynamicBonusFeeStart, beforeConfig.dynamicBonusFeeStart, "dynamic bonus changed");
        assertEq(
            afterConfig.dynamicBonusFeeDecaySteepness, beforeConfig.dynamicBonusFeeDecaySteepness, "bonus decay changed"
        );
        assertEq(afterConfig.liquidationBaseFee, beforeConfig.liquidationBaseFee, "base fee changed");
        assertEq(afterConfig.minPenaltyPercentage, beforeConfig.minPenaltyPercentage, "penalty changed");
        assertEq(afterConfig.protocolFeePercentage, beforeConfig.protocolFeePercentage, "protocol fee changed");
        assertEq(
            afterConfig.isEnabledPriorityLiquidation,
            beforeConfig.isEnabledPriorityLiquidation,
            "priority liquidation changed"
        );
        assertEq(
            afterConfig.disablePriorityLiquidationAbovePositionLtv,
            beforeConfig.disablePriorityLiquidationAbovePositionLtv,
            "priority cutoff changed"
        );
        assertEq(
            afterConfig.priorityLiquidationGracePeriod,
            beforeConfig.priorityLiquidationGracePeriod,
            "priority grace changed"
        );
        assertEq(
            afterConfig.taggerLiquidationGracePeriod, beforeConfig.taggerLiquidationGracePeriod, "tagger grace changed"
        );
        assertEq(afterConfig.liquidationWindowTag, beforeConfig.liquidationWindowTag, "window changed");
    }

    function _assertFrozenAndUnpaused(IMarketBase market) private view {
        assertTrue(market.paused(FROZEN_TYPE), "market not frozen");
        assertFalse(market.paused(PAUSE_TYPE), "market paused");
    }

    function _exerciseRepaymentAndCollateralWithdrawal() private {
        IMarket market = IMarket(borrowMarkets[0]);
        IERC20 borrowToken = IERC20(market.borrowToken());
        IERC20 collateralToken = IERC20(market.collateralToken());
        Position memory positionBefore = market.position(exitBorrower);

        deal(address(borrowToken), exitBorrower, 1_000 ether);
        vm.startPrank(exitBorrower);
        borrowToken.approve(address(market), type(uint256).max);
        market.repay(0, positionBefore.borrowShares, exitBorrower);
        market.removeCollateral(positionBefore.collateralAssets, exitBorrower, exitBorrower, "");
        vm.stopPrank();

        Position memory positionAfter = market.position(exitBorrower);
        assertEq(positionAfter.borrowShares, 0, "repayment route failed");
        assertEq(positionAfter.collateralAssets, 0, "collateral withdrawal route failed");
        assertEq(collateralToken.balanceOf(exitBorrower), positionBefore.collateralAssets, "wrong collateral returned");
    }

    function _exercisePermissionlessLiquidation() private {
        IMarket market = IMarket(borrowMarkets[0]);
        IERC20 borrowToken = IERC20(market.borrowToken());
        Position memory positionBefore = market.position(liquidationBorrower);

        deal(address(borrowToken), liquidator, 10_000 ether);
        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (uint256 seizedCollateral, uint256 repaidBorrow,) = market.liquidate(liquidationBorrower, "", "");
        vm.stopPrank();

        Position memory positionAfter = market.position(liquidationBorrower);
        assertGt(seizedCollateral, 0, "liquidation seized no collateral");
        assertGt(repaidBorrow, 0, "liquidation repaid no debt");
        assertLt(positionAfter.borrowShares, positionBefore.borrowShares, "liquidation did not reduce debt shares");
        assertLt(
            positionAfter.collateralAssets, positionBefore.collateralAssets, "liquidation did not reduce collateral"
        );
    }

    function _exerciseVaultWithdrawalWithoutLoss() private {
        IERC4626 erc4626Vault = IERC4626(address(vault));
        IERC20 borrowToken = IERC20(erc4626Vault.asset());
        uint256 assetsToWithdraw = 1 ether;
        uint256 receiverBalanceBefore = borrowToken.balanceOf(VAULT_SHARE_HOLDER);
        uint256 holderSharesBefore = erc4626Vault.balanceOf(VAULT_SHARE_HOLDER);
        uint256 vaultAssetsBefore = erc4626Vault.totalAssets();
        uint256 lostAssetsBefore = vault.lostAssets();

        assertGe(erc4626Vault.maxWithdraw(VAULT_SHARE_HOLDER), assetsToWithdraw, "Vault route lacks liquidity");
        vm.prank(VAULT_SHARE_HOLDER);
        uint256 burnedShares = erc4626Vault.withdraw(assetsToWithdraw, VAULT_SHARE_HOLDER, VAULT_SHARE_HOLDER);

        assertGt(burnedShares, 0, "Vault withdrawal burned no shares");
        assertEq(
            erc4626Vault.balanceOf(VAULT_SHARE_HOLDER),
            holderSharesBefore - burnedShares,
            "Vault withdrawal burned wrong shares"
        );
        assertEq(
            borrowToken.balanceOf(VAULT_SHARE_HOLDER),
            receiverBalanceBefore + assetsToWithdraw,
            "Vault withdrawal returned wrong assets"
        );
        assertApproxEqAbs(
            erc4626Vault.totalAssets(),
            vaultAssetsBefore - assetsToWithdraw,
            10,
            "Vault accounting does not match withdrawal"
        );
        assertEq(vault.lostAssets(), lostAssetsBefore, "Batch B created Vault loss");
    }
}
