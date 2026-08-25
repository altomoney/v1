// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboardingPhase} from "../IBorrowMarketOffboarding.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BatchBReduceLtvTest is BorrowMarketOffboardingTestBase {
    uint256 internal constant CORRECTION_RATE_SPY = 0.2 ether / uint256(365 days);
    uint256 internal constant LTV_REDUCTION = 0.05 ether;

    struct LtvMarketSnapshot {
        address irm;
        address liquidationEngine;
        uint256 maxLtv;
        LiquidationConfiguration liquidationConfiguration;
    }

    address[] internal boundaryBorrowers;
    address[] internal boundaryLiquidators;
    uint256[] internal boundaryPrices;
    LtvMarketSnapshot[] internal ltvSnapshots;

    function setUp() public {
        _setUpManifest();
        if (marketAlreadyFrozen) return;

        _seedStandardPositions();
        _seedBoundaryPositions();
        _ensureFactory();
        _executeContainmentPrerequisite();
        _assertAllFrozenAndUnpaused();
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertHealthyAndSnapshot(i);
        }
    }

    function testBatchBReducesLtvParametersAndPreservesExitAndLiquidationRoutes() public {
        if (marketAlreadyFrozen) return;

        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketReductionAndRoutes(i);
        }
    }

    function _assertMarketReductionAndRoutes(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        LtvMarketSnapshot memory beforeState = ltvSnapshots[marketIndex];
        LiquidationConfiguration memory afterConfig =
            IDcfDlbPriorityLiquidationEngine(beforeState.liquidationEngine).liquidationConfiguration();

        assertEq(market.irm(), beforeState.irm, "IRM address changed");
        assertEq(market.liquidationEngine(), beforeState.liquidationEngine, "liquidation engine changed");
        assertEq(market.maxLtv(), _reduce(beforeState.maxLtv), "wrong market max LTV");
        assertEq(
            afterConfig.maxLiquidationLtv,
            _reduce(beforeState.liquidationConfiguration.maxLiquidationLtv),
            "wrong maximum liquidation LTV"
        );
        assertEq(
            afterConfig.ltvForCompleteLiquidation,
            _reduce(beforeState.liquidationConfiguration.ltvForCompleteLiquidation),
            "wrong complete-liquidation LTV"
        );

        (uint256 borrowRate,) = FixedRateIrm(beforeState.irm).irState();
        assertEq(borrowRate, CORRECTION_RATE_SPY, "wrong corrected fixed rate");
        _assertValidConfiguration(market, afterConfig);
        _assertUnscheduledFieldsUnchanged(beforeState.liquidationConfiguration, afterConfig);
        _assertFrozenAndUnpaused(market);

        _liquidateBoundaryPosition(marketIndex);
        _exerciseExitAndLiquidationRoutes(market, fixtures[marketIndex]);
        _assertFrozenAndUnpaused(market);
    }

    function _seedBoundaryPositions() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            uint256 collateralAssets = 10 ** uint256(IERC20Metadata(market.collateralToken()).decimals()) / 100;
            uint256 collateralValue =
                Math.mulDiv(collateralAssets, fixtures[i].livePrice, LENDING_ORACLE_PRICE_PRECISION);
            uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);
            uint256 targetDebt = maximumBorrow - maximumBorrow / 1_000_000;
            uint256 borrowAssets = Math.mulDiv(targetDebt, 1 ether, 1 ether + market.borrowOpeningFee()) - 1;
            address borrower = makeAddr(string.concat("boundary-borrower-", vm.toString(i)));

            IERC20 borrowToken = IERC20(market.borrowToken());
            address supplier = makeAddr(string.concat("boundary-supplier-", vm.toString(i)));
            deal(address(borrowToken), supplier, maximumBorrow);
            vm.startPrank(supplier);
            borrowToken.approve(address(market), maximumBorrow);
            market.addSupply(maximumBorrow, 0, supplier);
            vm.stopPrank();

            _openBorrowPosition(market, borrower, collateralAssets, borrowAssets);
            boundaryBorrowers.push(borrower);
            boundaryLiquidators.push(makeAddr(string.concat("boundary-liquidator-", vm.toString(i))));
            boundaryPrices.push(Math.mulDiv(fixtures[i].livePrice, 99, 100));
        }
    }

    function _assertHealthyAndSnapshot(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address liquidationEngine = market.liquidationEngine();
        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(boundaryPrices[marketIndex]));

        IERC20 borrowToken = IERC20(market.borrowToken());
        address liquidator = boundaryLiquidators[marketIndex];
        deal(address(borrowToken), liquidator, 1_000_000 ether);
        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (bool liquidated, bytes memory returnData) = address(market).call(
            abi.encodeCall(IMarketBase.liquidate, (boundaryBorrowers[marketIndex], bytes(""), bytes("")))
        );
        vm.stopPrank();

        assertFalse(liquidated, "boundary position liquidatable before LTV reduction");
        assertEq(
            returnData,
            abi.encodeWithSelector(
                IDcfDlbPriorityLiquidationEngineErrors
                    .DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition
                    .selector
            ),
            "unexpected pre-reduction liquidation revert"
        );

        ltvSnapshots.push(
            LtvMarketSnapshot({
                irm: market.irm(),
                liquidationEngine: liquidationEngine,
                maxLtv: market.maxLtv(),
                liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration()
            })
        );
    }

    function _liquidateBoundaryPosition(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address borrower = boundaryBorrowers[marketIndex];
        address liquidator = boundaryLiquidators[marketIndex];
        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(boundaryPrices[marketIndex]));

        Position memory beforePosition = market.position(borrower);
        IERC20 borrowToken = IERC20(market.borrowToken());
        deal(address(borrowToken), liquidator, 1_000_000 ether);
        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (uint256 seizedCollateral, uint256 repaidBorrow,) = market.liquidate(borrower, "", "");
        vm.stopPrank();

        Position memory afterPosition = market.position(borrower);
        assertGt(seizedCollateral, 0, "newly liquidatable position seized no collateral");
        assertGt(repaidBorrow, 0, "newly liquidatable position repaid no debt");
        assertLt(afterPosition.borrowShares, beforePosition.borrowShares, "boundary debt was not reduced");
        assertLt(afterPosition.collateralAssets, beforePosition.collateralAssets, "boundary collateral was not seized");
    }

    function _assertValidConfiguration(IMarket market, LiquidationConfiguration memory config) private view {
        assertLe(market.maxLtv(), config.maxLiquidationLtv, "market/liquidation LTV order invalid");
        assertLe(config.maxLiquidationLtv, config.ltvForCompleteLiquidation, "liquidation/complete LTV order invalid");
        assertLe(config.ltvForCompleteLiquidation, 1 ether, "complete-liquidation LTV above 100%");
        assertGt(config.dynamicBonusFeeDecaySteepness, 0, "zero bonus decay steepness");
        assertLe(config.dynamicBonusFeeDecaySteepness, 100 ether, "bonus decay steepness too high");

        uint256 totalLiquidationFee = config.dynamicBonusFeeStart + config.liquidationBaseFee;
        assertLe(totalLiquidationFee, 0.15 ether, "liquidation fee above maximum");
        assertLe(totalLiquidationFee, 1 ether - config.maxLiquidationLtv, "fee incompatible with liquidation LTV");
        assertLe(config.minPenaltyPercentage, 1 ether, "minimum penalty above 100%");
        assertLe(config.protocolFeePercentage, 1 ether, "protocol fee above 100%");
        if (config.protocolFeePercentage != 0) assertNotEq(market.feeRecipient(), address(0), "zero fee recipient");
        assertLe(config.priorityLiquidationGracePeriod, 1 hours, "priority grace period too long");
        assertLe(config.taggerLiquidationGracePeriod, 30 minutes, "tagger grace period too long");
        assertLe(config.liquidationWindowTag, 3 days, "liquidation window too long");
        assertLe(
            config.priorityLiquidationGracePeriod + config.taggerLiquidationGracePeriod,
            config.liquidationWindowTag,
            "grace periods exceed liquidation window"
        );
    }

    function _assertUnscheduledFieldsUnchanged(
        LiquidationConfiguration memory beforeConfig,
        LiquidationConfiguration memory afterConfig
    ) private pure {
        assertEq(afterConfig.dynamicBonusFeeStart, beforeConfig.dynamicBonusFeeStart, "dynamic bonus changed");
        assertEq(
            afterConfig.dynamicBonusFeeDecaySteepness, beforeConfig.dynamicBonusFeeDecaySteepness, "bonus decay changed"
        );
        assertEq(afterConfig.liquidationBaseFee, beforeConfig.liquidationBaseFee, "base fee changed");
        assertEq(afterConfig.minPenaltyPercentage, beforeConfig.minPenaltyPercentage, "minimum penalty changed");
        assertEq(afterConfig.protocolFeePercentage, beforeConfig.protocolFeePercentage, "protocol fee changed");
        assertEq(
            afterConfig.isEnabledPriorityLiquidation,
            beforeConfig.isEnabledPriorityLiquidation,
            "priority liquidation flag changed"
        );
        assertEq(
            afterConfig.disablePriorityLiquidationAbovePositionLtv,
            beforeConfig.disablePriorityLiquidationAbovePositionLtv,
            "priority-liquidation cutoff changed"
        );
        assertEq(
            afterConfig.priorityLiquidationGracePeriod,
            beforeConfig.priorityLiquidationGracePeriod,
            "priority grace period changed"
        );
        assertEq(
            afterConfig.taggerLiquidationGracePeriod,
            beforeConfig.taggerLiquidationGracePeriod,
            "tagger grace period changed"
        );
        assertEq(afterConfig.liquidationWindowTag, beforeConfig.liquidationWindowTag, "liquidation window changed");
    }

    function _reduce(uint256 value) private pure returns (uint256) {
        return value > LTV_REDUCTION ? value - LTV_REDUCTION : 0;
    }
}
