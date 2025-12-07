// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineEvents,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";

contract AltoMarketSetLiquidationConfiguration is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    LiquidationConfiguration VALID_CONFIGURATION = LiquidationConfiguration({
        maxLiquidationLtv: 0.85 ether,
        dynamicBonusFeeStart: 0.03 ether,
        ltvForCompleteLiquidation: 0.95 ether,
        dynamicBonusFeeDecaySteepness: 10 ether,
        liquidationBaseFee: 0.05 ether,
        minPenaltyPercentage: 0.02 ether,
        protocolFeePercentage: 0 ether,
        isEnabledPriorityLiquidation: true,
        disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
        priorityLiquidationGracePeriod: 10 minutes,
        taggerLiquidationGracePeriod: 5 minutes,
        liquidationWindowTag: 1 days
    });

    function test_RevertWhen_CallerIsNotOwner() external {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        liquidationEngine.setLiquidationConfiguration(VALID_CONFIGURATION);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        LiquidationConfiguration memory oldLiquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();

        // it should emit SetLiquidationConfiguration event
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        vm.expectEmit();
        emit IDcfDlbPriorityLiquidationEngineEvents.SetLiquidationConfiguration(
            oldLiquidationConfiguration, VALID_CONFIGURATION
        );
        liquidationEngine.setLiquidationConfiguration(VALID_CONFIGURATION);

        // it should update liquidation configuration
        LiquidationConfiguration memory config = liquidationEngine.liquidationConfiguration();
        assertEq(config.maxLiquidationLtv, VALID_CONFIGURATION.maxLiquidationLtv);
        assertEq(config.dynamicBonusFeeStart, VALID_CONFIGURATION.dynamicBonusFeeStart);
        assertEq(config.ltvForCompleteLiquidation, VALID_CONFIGURATION.ltvForCompleteLiquidation);
        assertEq(config.dynamicBonusFeeDecaySteepness, VALID_CONFIGURATION.dynamicBonusFeeDecaySteepness);
        assertEq(
            config.disablePriorityLiquidationAbovePositionLtv,
            VALID_CONFIGURATION.disablePriorityLiquidationAbovePositionLtv
        );
        assertEq(config.isEnabledPriorityLiquidation, VALID_CONFIGURATION.isEnabledPriorityLiquidation);
        assertEq(config.liquidationBaseFee, VALID_CONFIGURATION.liquidationBaseFee);
        assertEq(config.minPenaltyPercentage, VALID_CONFIGURATION.minPenaltyPercentage);
        assertEq(config.protocolFeePercentage, VALID_CONFIGURATION.protocolFeePercentage);
        assertEq(config.priorityLiquidationGracePeriod, VALID_CONFIGURATION.priorityLiquidationGracePeriod);
    }

    function test_RevertWhen_MaxLiquidationLtvIsLessThanMaxLtv() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.maxLiquidationLtv = market.maxLtv() - 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_LtvForCompleteLiquidationIsLessThanMaxLiquidationLtv() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.ltvForCompleteLiquidation = liquidationConfiguration.maxLiquidationLtv - 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_LtvForCompleteLiquidationIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.ltvForCompleteLiquidation = MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_DynamicBonusFeeDecaySteepnessIsInvalid() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.dynamicBonusFeeDecaySteepness = 100 * MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);

        liquidationConfiguration.dynamicBonusFeeDecaySteepness = 0;
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_SumOfDynamicBonusFeeStartAndLiquidationBaseFeeIsGreaterThan0Point15ether()
        external
        whenCallerIsOwner
    {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.dynamicBonusFeeStart = 0.09 ether;
        liquidationConfiguration.liquidationBaseFee = 0.15 ether - 0.09 ether + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_SumOfDynamicBonusFeeStartAndLiquidationBaseFeeIsGreaterThan1EtherMinusMaxLiquidationLtv()
        external
        whenCallerIsOwner
    {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.dynamicBonusFeeStart = 0;
        liquidationConfiguration.liquidationBaseFee = 1 ether - liquidationConfiguration.maxLiquidationLtv + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_MinPenaltyPercentageIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.minPenaltyPercentage = MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_ProtocolFeePercentageIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_FeeRecipientIsNotSetAndProtocolFeePercentageIsMoreThan0() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfigurationPre = liquidationEngine.liquidationConfiguration();
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();

        liquidationConfigurationPre.protocolFeePercentage = 0;
        liquidationEngine.setLiquidationConfiguration(liquidationConfigurationPre);
        market.setIrm(address(0), false);
        market.setFeeRecipient(address(0));

        liquidationConfiguration.protocolFeePercentage = 0.01 ether;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_PriorityLiquidationGracePeriodIsGreaterThan1Hour() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.priorityLiquidationGracePeriod = 1 hours + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_TaggerLiquidationGracePeriodIsGreaterThan30Minutes() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.taggerLiquidationGracePeriod = 30 minutes + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_LiquidationWindowTagIsGreaterThan3Days() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.liquidationWindowTag = 3 days + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }

    function test_RevertWhen_GracePeriodsSumIsGreaterThanLiquidationWindowTag() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.priorityLiquidationGracePeriod = 1 hours;
        liquidationConfiguration.taggerLiquidationGracePeriod = 30 minutes;
        liquidationConfiguration.liquidationWindowTag = 1 hours;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector)
        );
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);
    }
}
