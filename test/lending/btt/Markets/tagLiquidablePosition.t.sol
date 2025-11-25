// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {
    IMarketErrors,
    IMarketEvents
} from "@alto/lending/interfaces/IMarket.sol";
import {
    LiquidablePosition,
    LiquidationConfiguration,
    IPriorityLiquidationEngineErrors
} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {
    IPriorityLiquidationEngine,
    IPriorityLiquidationEngineEvents
} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";

contract AltoMarketTagLiquidablePosition is MarketCommon {
    using AssetShareConversionMath for uint256;

    address internal immutable PRIORITY_LIQUIDATOR = makeAddr("PriorityLiquidator");

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        liquidationEngine.tagLiquidablePosition(USER, USER);
    }

    function test_RevertWhen_PriorityLiquidationIsDisabled() external {
        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        LiquidationConfiguration memory liquidationConfiguration = liquidationEngine.liquidationConfiguration();
        liquidationConfiguration.isEnabledPriorityLiquidation = false;
        vm.prank(OWNER);
        liquidationEngine.setLiquidationConfiguration(liquidationConfiguration);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEnginePriorityLiquidationDisabled.selector));
        liquidationEngine.tagLiquidablePosition(USER, USER);
    }

    function test_GivenUserPositionIsSolvent() external {
        deal(address(collateralToken), address(this), 1000 ether);
        deal(address(borrowToken), address(this), 1000 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(1000 ether, 0, SUPPLIER);
        }
        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, hex"");

        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert with AltoPriorityLiquidationEngineLiquidatingSolventPosition
        vm.expectRevert(abi.encodeWithSelector(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidatingSolventPosition.selector));
        liquidationEngine.tagLiquidablePosition(USER, address(this));
    }

    modifier givenUserPositionIsNotSolvent() {
        vm.startPrank(OWNER);
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))), false);
        IPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
        vm.stopPrank();

        deal(address(collateralToken), address(this), 1 ether);
        deal(address(borrowToken), address(this), 1 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(0.5 ether, 0, SUPPLIER);
        }

        if (marketType == MarketType.MINT) {
            vm.startPrank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(0.5 ether);
            vm.stopPrank();
        }

        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, hex"");

        vm.warp(block.timestamp + 100 days);
        _;
    }

    function test_WhenLiquidatorIsAPriorityLiquidator() external givenUserPositionIsNotSolvent {
        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert with AltoPriorityLiquidationEngineLiquidationUnauthorized
        vm.expectRevert(abi.encodeWithSelector(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidationUnauthorized.selector));
        liquidationEngine.tagLiquidablePosition(USER, PRIORITY_LIQUIDATOR);
    }

    modifier whenUserHasAlreadyBeenTagged() {
        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        liquidationEngine.tagLiquidablePosition(USER, LIQUIDATOR);
        _;
    }

    function test_WhenLiquidationWindowTagHasNotExpired()
        external
        givenUserPositionIsNotSolvent
        whenUserHasAlreadyBeenTagged
    {
        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert with AltoPriorityLiquidationEngineLiquidationAlreadyTagged
        vm.expectRevert(abi.encodeWithSelector(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidationAlreadyTagged.selector));
        liquidationEngine.tagLiquidablePosition(USER, LIQUIDATOR);
    }

    function test_WhenLiquidationWindowTagHasExpired()
        external
        givenUserPositionIsNotSolvent
        whenUserHasAlreadyBeenTagged
    {
        // skip time to make liquidation window tag expired
        vm.warp(block.timestamp + 100 days);

        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);

        // it should emit PositionTagged event
        vm.expectEmit();
        emit IPriorityLiquidationEngineEvents.PositionTagged(USER, LIQUIDATOR, block.timestamp);
        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        liquidationEngine.tagLiquidablePosition(USER, LIQUIDATOR);

        LiquidablePosition memory liquidablePositionAfter =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidablePositions(USER);

        // it should update liquidablePositions
        assertEq(liquidablePositionAfter.tagged, true);
        assertEq(liquidablePositionAfter.tagger, LIQUIDATOR);
        assertEq(liquidablePositionAfter.timestamp, block.timestamp);
    }

    function test_WhenUserHasNotBeenTagged() external givenUserPositionIsNotSolvent {
        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);

        // it should emit PositionTagged event
        vm.expectEmit();
        emit IPriorityLiquidationEngineEvents.PositionTagged(USER, LIQUIDATOR, block.timestamp);
        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());
        liquidationEngine.tagLiquidablePosition(USER, LIQUIDATOR);

        LiquidablePosition memory liquidablePositionAfter =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidablePositions(USER);

        // it should update liquidablePositions
        assertEq(liquidablePositionAfter.tagged, true);
        assertEq(liquidablePositionAfter.tagger, LIQUIDATOR);
        assertEq(liquidablePositionAfter.timestamp, block.timestamp);
    }
}
