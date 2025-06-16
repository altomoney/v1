// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract AltoMarketSetLiquidationConfiguration is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    LiquidationConfiguration VALID_CONFIGURATION = LiquidationConfiguration({
        maxLiquidationLtv: 0.85 ether,
        dynamicBonusFeeStart: 0.09 ether,
        ltvForCompleteLiquidation: 0.95 ether,
        dynamicBonusFeeDecaySteepness: 10 ether,
        liquidationBaseFee: 0.07 ether,
        minPenaltyPercentage: 0.02 ether,
        isEnabledPriorityLiquidation: true,
        disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
        priorityLiquidationGracePeriod: 10 minutes,
        taggerLiquidationGracePeriod: 5 minutes,
        liquidationWindowTag: 1 days
    });

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setLiquidationConfiguration(VALID_CONFIGURATION);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        LiquidationConfiguration memory oldLiquidationConfiguration = market.liquidationConfiguration();

        // it should emit SetLiquidationConfiguration event
        vm.expectEmit();
        emit IMarketEvents.SetLiquidationConfiguration(oldLiquidationConfiguration, VALID_CONFIGURATION);

        market.setLiquidationConfiguration(VALID_CONFIGURATION);

        // it should update liquidation configuration
        assertEq(market.liquidationConfiguration().maxLiquidationLtv, VALID_CONFIGURATION.maxLiquidationLtv);
        assertEq(market.liquidationConfiguration().dynamicBonusFeeStart, VALID_CONFIGURATION.dynamicBonusFeeStart);
        assertEq(
            market.liquidationConfiguration().ltvForCompleteLiquidation, VALID_CONFIGURATION.ltvForCompleteLiquidation
        );
        assertEq(
            market.liquidationConfiguration().dynamicBonusFeeDecaySteepness,
            VALID_CONFIGURATION.dynamicBonusFeeDecaySteepness
        );
        assertEq(
            market.liquidationConfiguration().disablePriorityLiquidationAbovePositionLtv,
            VALID_CONFIGURATION.disablePriorityLiquidationAbovePositionLtv
        );
        assertEq(
            market.liquidationConfiguration().isEnabledPriorityLiquidation,
            VALID_CONFIGURATION.isEnabledPriorityLiquidation
        );
        assertEq(market.liquidationConfiguration().liquidationBaseFee, VALID_CONFIGURATION.liquidationBaseFee);
        assertEq(market.liquidationConfiguration().minPenaltyPercentage, VALID_CONFIGURATION.minPenaltyPercentage);
        assertEq(
            market.liquidationConfiguration().priorityLiquidationGracePeriod,
            VALID_CONFIGURATION.priorityLiquidationGracePeriod
        );
    }

    function test_RevertWhen_MaxLiquidationLtvIsLessThanMaxLtv() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.maxLiquidationLtv = market.maxLtv() - 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_LtvForCompleteLiquidationIsLessThanMaxLiquidationLtv() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.ltvForCompleteLiquidation = liquidationConfiguration.maxLiquidationLtv - 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_LtvForCompleteLiquidationIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.ltvForCompleteLiquidation = MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_DynamicBonusFeeDecaySteepnessIsInvalid() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.dynamicBonusFeeDecaySteepness = 100 * MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);

        liquidationConfiguration.dynamicBonusFeeDecaySteepness = 0;
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_SumOfDynamicBonusFeeStartAndLiquidationBaseFeeIsGreaterThanMATH_PRECISION()
        external
        whenCallerIsOwner
    {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.dynamicBonusFeeStart = 0.5 ether;
        liquidationConfiguration.liquidationBaseFee = 0.6 ether;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_MinPenaltyPercentageIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.minPenaltyPercentage = MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_PriorityLiquidationGracePeriodIsGreaterThan1Hour() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.priorityLiquidationGracePeriod = 1 hours + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_TaggerLiquidationGracePeriodIsGreaterThan30Minutes() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.taggerLiquidationGracePeriod = 30 minutes + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_LiquidationWindowTagIsGreaterThan3Days() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.liquidationWindowTag = 3 days + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_GracePeriodsSumIsGreaterThanLiquidationWindowTag() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.priorityLiquidationGracePeriod = 1 hours;
        liquidationConfiguration.taggerLiquidationGracePeriod = 30 minutes;
        liquidationConfiguration.liquidationWindowTag = 1 hours;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(liquidationConfiguration);
    }
}
