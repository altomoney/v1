// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";

import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IRState} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";

import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmMarketIntegrationTest is PegResponsiveExponentialIrmCommon {
    function setUp() public override {
        super.setUp();
        _bindMarket();
    }

    function test_WhenMintMarketAccrues_ItAppliesDebtAndFeeAccountingWithoutChangingShares() external {
        _openDebt(1_000e18);
        (uint128 debtAssetsBefore, uint128 debtSharesBefore) = market.totalBorrowed();
        (uint128 supplyAssetsBefore, uint128 supplySharesBefore) = market.totalSupply();
        uint128 claimableFeesBefore = market.claimableFeesAssets();
        IRState memory stateBefore = _readIRState();

        vm.warp(block.timestamp + 30 days);
        _setCurrentObservation(MID_BRIDGE_PRICE);
        uint256 expectedInterest =
            _expectedInterest(debtAssetsBefore, stateBefore.borrowRate, block.timestamp - stateBefore.lastUpdate);

        vm.expectEmit(false, false, false, true, address(market));
        emit IMarketEvents.AccrueInterest(
            stateBefore.borrowRate,
            expectedInterest,
            uint128(uint256(debtAssetsBefore) + expectedInterest),
            supplyAssetsBefore
        );
        market.accrueInterest();

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = market.totalBorrowed();
        (uint128 supplyAssetsAfter, uint128 supplySharesAfter) = market.totalSupply();
        IRState memory stateAfter = _readIRState();

        assertGt(expectedInterest, 0, "expected positive interest");
        assertEq(debtAssetsAfter, uint256(debtAssetsBefore) + expectedInterest, "debt assets");
        assertEq(debtSharesAfter, debtSharesBefore, "debt shares");
        assertEq(supplyAssetsAfter, supplyAssetsBefore, "debt ceiling");
        assertEq(supplySharesAfter, supplySharesBefore, "supply shares");
        assertEq(market.claimableFeesAssets(), uint256(claimableFeesBefore) + expectedInterest, "claimable fees");
        assertEq(stateAfter.borrowRate, irm.targetBorrowRate(MID_BRIDGE_PRICE), "prospective rate");
        assertEq(stateAfter.lastUpdate, block.timestamp, "checkpoint time");
    }

    function test_RepeatedMintMarketCheckpointsAccumulateAgainstUpdatedDebtWithoutReplacingShares() external {
        _openDebt(1_000e18);
        (uint128 initialDebtAssets, uint128 initialDebtShares) = market.totalBorrowed();

        IRState memory firstStateBefore = _readIRState();
        vm.warp(block.timestamp + 1 days);
        _setCurrentObservation(RECOVERY_PRICE);
        uint256 firstInterest = _expectedInterest(
            initialDebtAssets, firstStateBefore.borrowRate, block.timestamp - firstStateBefore.lastUpdate
        );
        market.accrueInterest();

        (uint128 firstDebtAssets, uint128 firstDebtShares) = market.totalBorrowed();
        IRState memory secondStateBefore = _readIRState();
        vm.warp(block.timestamp + 1 days);
        _setCurrentObservation(RECOVERY_PRICE);
        uint256 secondInterest = _expectedInterest(
            firstDebtAssets, secondStateBefore.borrowRate, block.timestamp - secondStateBefore.lastUpdate
        );
        market.accrueInterest();

        (uint128 finalDebtAssets, uint128 finalDebtShares) = market.totalBorrowed();
        assertEq(firstDebtAssets, uint256(initialDebtAssets) + firstInterest, "first accumulated debt");
        assertEq(finalDebtAssets, uint256(firstDebtAssets) + secondInterest, "second accumulated debt");
        assertEq(firstDebtShares, initialDebtShares, "first shares");
        assertEq(finalDebtShares, initialDebtShares, "final shares");
        assertEq(market.claimableFeesAssets(), firstInterest + secondInterest, "cumulative fees");
    }

    function test_ZeroDebtMintMarketCheckpointStillUpdatesControllerWithoutCreatingAccounting() external {
        vm.warp(block.timestamp + 1 days);
        _setCurrentObservation(STRESS_PRICE);

        market.accrueInterest();

        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        IRState memory stateAfter = _readIRState();
        assertEq(debtAssets, 0, "debt assets");
        assertEq(debtShares, 0, "debt shares");
        assertEq(market.claimableFeesAssets(), 0, "claimable fees");
        assertEq(stateAfter.borrowRate, STRESS_RATE, "stress rate");
        assertEq(stateAfter.lastUpdate, block.timestamp, "checkpoint time");
        assertTrue(stateAfter.stressMode, "stress mode");
    }

    function test_RevertWhenMintMarketCannotApplyInterest_RollsBackControllerAndAccounting() external {
        _prepareMarketAccrualOverflow();
        IRState memory stateBefore = _readIRState();
        (uint128 debtAssetsBefore, uint128 debtSharesBefore) = market.totalBorrowed();
        uint128 claimableFeesBefore = market.claimableFeesAssets();
        uint256 expectedInterest =
            _expectedInterest(debtAssetsBefore, stateBefore.borrowRate, block.timestamp - stateBefore.lastUpdate);

        assertGt(expectedInterest, 0, "expected positive interest");
        assertLe(expectedInterest, type(uint128).max, "interest conversion must succeed");
        assertEq(claimableFeesBefore, type(uint128).max, "saturated fees");

        vm.expectRevert(stdError.arithmeticError);
        market.accrueInterest();

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = market.totalBorrowed();
        _assertIRState(stateBefore);
        assertEq(debtAssetsAfter, debtAssetsBefore, "debt rollback");
        assertEq(debtSharesAfter, debtSharesBefore, "share rollback");
        assertEq(market.claimableFeesAssets(), claimableFeesBefore, "fee rollback");
    }

    function test_WhenInterestRoundsBelowOneAsset_ItUpdatesControllerWithoutChangingAccounting() external {
        uint256 borrowedAssets = 1e18 - 1;
        _openDebt(borrowedAssets);
        (uint128 debtAssetsBefore, uint128 debtSharesBefore) = market.totalBorrowed();
        _setIRState(1, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 1);
        _setCurrentObservation(RECOVERY_PRICE);

        assertEq(_expectedInterest(debtAssetsBefore, 1, 1), 0, "rounded interest");
        market.accrueInterest();

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = market.totalBorrowed();
        assertEq(debtAssetsAfter, debtAssetsBefore, "debt assets");
        assertEq(debtSharesAfter, debtSharesBefore, "debt shares");
        assertEq(market.claimableFeesAssets(), 0, "claimable fees");
        assertEq(_readIRState().lastUpdate, block.timestamp, "controller checkpoint");
    }

    function test_WhenDebtSharesEqualUint128Maximum_RepeatedAccrualReachesAssetAdditionBoundary() external {
        _openMaximumDebtPosition(address(0xA001));
        (, uint128 debtSharesBefore) = market.totalBorrowed();
        assertEq(debtSharesBefore, type(uint128).max, "maximum reachable debt shares");

        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        _setCurrentObservation(RECOVERY_PRICE);
        market.accrueInterest();
        assertEq(_readIRState().lastUpdate, block.timestamp, "zero elapsed checkpoint");

        _accrueMaximumCompoundInterest();
        _accrueMaximumCompoundInterest();
        (uint128 debtAssetsBefore,) = market.totalBorrowed();
        uint128 claimableFeesBefore = market.claimableFeesAssets();
        uint256 elapsed = _maximumElapsedWithUint128Interest(debtAssetsBefore);
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + elapsed);
        _setCurrentObservation(RECOVERY_PRICE);
        IRState memory stateBefore = _readIRState();
        uint256 expectedInterest = _expectedInterest(debtAssetsBefore, MAX_RATE, elapsed);
        assertLe(expectedInterest, type(uint128).max, "interest itself fits uint128");
        assertGt(uint256(debtAssetsBefore) + expectedInterest, type(uint128).max, "debt addition boundary");

        vm.expectRevert(stdError.arithmeticError);
        market.accrueInterest();

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = market.totalBorrowed();
        _assertIRState(stateBefore);
        assertEq(debtAssetsAfter, debtAssetsBefore, "debt assets rollback");
        assertEq(debtSharesAfter, debtSharesBefore, "debt shares rollback");
        assertEq(market.claimableFeesAssets(), claimableFeesBefore, "fees rollback");
    }

    function test_RevertWhenRepeatedAccrualReturnsInterestAboveUint128_RollsBackEverything() external {
        _openMaximumDebtPosition(address(0xA001));
        _accrueMaximumCompoundInterest();
        _accrueMaximumCompoundInterest();
        (uint128 debtAssetsBefore, uint128 debtSharesBefore) = market.totalBorrowed();
        uint128 claimableFeesBefore = market.claimableFeesAssets();
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 200 * YEAR);
        _setCurrentObservation(RECOVERY_PRICE);

        IRState memory stateBefore = _readIRState();
        uint256 expectedInterest = _expectedInterest(debtAssetsBefore, MAX_RATE, 200 * YEAR);
        assertGt(expectedInterest, type(uint128).max, "conversion boundary");

        vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
        market.accrueInterest();

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = market.totalBorrowed();
        _assertIRState(stateBefore);
        assertEq(debtAssetsAfter, debtAssetsBefore, "debt assets rollback");
        assertEq(debtSharesAfter, debtSharesBefore, "debt shares rollback");
        assertEq(market.claimableFeesAssets(), claimableFeesBefore, "fees rollback");
    }

    function test_BorrowCheckpointsControllerThroughMintMarket() external {
        _openDebt(100e18);
        _prepareActionCheckpoint();
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        market.borrow(1e18, 0, address(this), address(this), hex"");

        _assertActionCheckpointed();
    }

    function test_RemoveCollateralCheckpointsControllerThroughMintMarket() external {
        _openDebt(100e18);
        _prepareActionCheckpoint();
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        market.removeCollateral(1e18, address(this), address(this), hex"");

        _assertActionCheckpointed();
    }

    function test_RepayPerformsBothMintAndBaseMarketCheckpoints() external {
        _openDebt(100e18);
        _prepareActionCheckpoint();
        vm.expectCall(address(oracle), _getPriceCall(), 2);

        market.repay(1e18, 0, address(this));

        _assertActionCheckpointed();
    }

    function test_SetDebtCeilingCheckpointsControllerThroughMintMarket() external {
        _openDebt(100e18);
        _prepareActionCheckpoint();
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        market.setDebtCeiling(type(uint128).max - 1);

        _assertActionCheckpointed();
    }

    function test_SetIrmCheckpointsOldControllerThroughMintMarket() external {
        _openDebt(100e18);
        _prepareActionCheckpoint();
        address replacement = address(_deployIrm(irmConfig));
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        market.setIrm(replacement, false);

        _assertActionCheckpointed();
        assertEq(market.irm(), replacement, "replacement IRM");
    }

    function test_GovernanceLiquidationCheckpointsControllerThroughMintMarket() external {
        _openDebt(100e18);
        _prepareActionCheckpoint();
        vm.expectCall(address(oracle), _getPriceCall(), 1);

        vm.prank(OWNER);
        market.governanceLiquidate(address(this), false);

        _assertActionCheckpointed();
        assertGt(market.badDebtAssets(), 100e18, "bad debt includes accrued interest");
    }

    function test_LiquidationPerformsBothMintAndBaseMarketCheckpoints() external {
        address borrower = address(0xB001);
        _configureLiquidation();
        _openDebtFor(borrower, 0.5e18, 1e18);
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 100 days);
        _setCurrentObservation(RECOVERY_PRICE);
        borrowToken.mint(address(this), 100e18);
        vm.expectCall(address(oracle), _getPriceCall(), 2);

        (uint256 seizedCollateral, uint256 repaidAssets,) = market.liquidate(borrower, hex"", hex"");

        assertGt(seizedCollateral, 0, "seized collateral");
        assertGt(repaidAssets, 0, "repaid assets");
        _assertActionCheckpointed();
    }

    function _prepareActionCheckpoint() private {
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 1 days);
        _setCurrentObservation(RECOVERY_PRICE);
    }

    function _assertActionCheckpointed() private view {
        IRState memory state = _readIRState();
        assertEq(state.lastUpdate, block.timestamp, "controller checkpoint");
    }

    function _openDebtFor(address borrower, uint256 borrowedAssets, uint256 collateralAssets) private {
        assertEq(borrower.code.length, 0, "borrower must be an EOA");
        deal(address(collateralToken), borrower, collateralAssets);

        vm.startPrank(borrower);
        collateralToken.approve(address(market), collateralAssets);
        market.addCollateral(collateralAssets, borrower);
        market.borrow(borrowedAssets, 0, borrower, borrower, hex"");
        vm.stopPrank();
    }

    function _openMaximumDebtPosition(address borrower) private returns (uint256 borrowedAssets) {
        assertEq(borrower.code.length, 0, "borrower must be an EOA");
        uint256 collateralAssets = type(uint128).max;
        deal(address(collateralToken), borrower, collateralAssets);

        vm.startPrank(borrower);
        collateralToken.approve(address(market), collateralAssets);
        market.addCollateral(collateralAssets, borrower);
        (borrowedAssets,,) = market.borrow(0, type(uint128).max, borrower, borrower, hex"");
        vm.stopPrank();
    }

    function _accrueMaximumCompoundInterest() private {
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 200 * YEAR);
        _setCurrentObservation(RECOVERY_PRICE);
        market.accrueInterest();
    }

    function _maximumElapsedWithUint128Interest(uint256 debtAssets) private pure returns (uint256 elapsed) {
        uint256 low;
        uint256 high = 200 * YEAR;
        while (low < high) {
            uint256 midpoint = (low + high + 1) / 2;
            if (_expectedInterest(debtAssets, MAX_RATE, midpoint) <= type(uint128).max) {
                low = midpoint;
            } else {
                high = midpoint - 1;
            }
        }
        return low;
    }

    function _configureLiquidation() private {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8e18,
            dynamicBonusFeeStart: 0.03e18,
            ltvForCompleteLiquidation: 0.9e18,
            dynamicBonusFeeDecaySteepness: 5e18,
            liquidationBaseFee: 0.05e18,
            minPenaltyPercentage: 0.01e18,
            protocolFeePercentage: 0,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(OWNER);
        liquidationEngine.setLiquidationConfiguration(config);
        liquidationEngine.setPriorityLiquidator(address(this), true);
        vm.stopPrank();
    }
}
