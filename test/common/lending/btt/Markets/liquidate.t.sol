// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {
    IMarketErrors,
    IMarketEvents,
    Position,
    Balance,
    LiquidablePosition,
    LiquidationConfiguration
} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOracle, ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

contract LiquidateCallback is ILiquidateCallback {
    event LiquidateCallbackCalled(uint256 collateralAmount, bytes data);

    function onLiquidateCallback(uint256 collateralAmount, bytes calldata data) external {
        emit LiquidateCallbackCalled(collateralAmount, data);
    }
}

contract AltoBorrowMarketliquidate is MarketCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    address internal immutable PRIORITY_LIQUIDATOR = makeAddr("PriorityLiquidator");
    address internal immutable TAGGER = makeAddr("Tagger");
    address internal immutable EXTERNAL_LIQUIDATOR = makeAddr("ExternalLiquidator");

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function getCurrentLtv(address user) public view returns (uint256) {
        Position memory position = market.position(user);
        Balance memory totalBorrowed = market.totalBorrowed();
        uint256 collateralValue = uint256(position.collateralAssets).divideWithRounding(
            IOracle(oracle).getPrice(), ORACLE_PRICE_PRECISION, false
        );
        uint256 positionBorrowedAssets =
            uint256(position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        return positionBorrowedAssets.divideWithPrecisionUp(collateralValue);
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.liquidate(USER, "");
    }

    function test_GivenPositionIsSolvent() external {
        deal(address(collateralToken), address(this), 1000 ether);
        deal(address(borrowToken), address(this), 1000 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(1000 ether, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(1000 ether);
        }
        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, "");

        // it should revert with AltoBaseMarketLiquidatingSolventPosition
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidatingSolventPosition.selector);
        market.liquidate(USER, "");
    }

    modifier givenPositionIsInsolvent() {
        vm.startPrank(OWNER);
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))));
        market.setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
        vm.stopPrank();

        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), 100 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(100 ether, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(100 ether);
            vm.stopPrank();
        }

        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, "");

        vm.warp(block.timestamp + 100 days);
        _;
    }

    modifier whenPriorityLiquidationIsEnabled() {
        // it is enabled by default
        _;
    }

    modifier whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold() {
        // it is below by default as disablePriorityLiquidationAbovePositionLtv is set to type(uint256).max
        _;
    }

    modifier whenLiquidatorIsNotPriorityLiquidator() {
        _;
    }

    function test_WhenPositionIsNotTagged()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
    {
        // it should revert with AltoBaseMarketLiquidationUnauthorized
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(USER, "");
    }

    modifier whenPositionIsTagged() {
        market.tagLiquidablePosition(USER, TAGGER);
        _;
    }

    modifier whenLiquidatorIsTheTagger() {
        _;
    }

    function test_WhenPriorityLiquidationGracePeriodHasNotElapsed()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsTheTagger
    {
        // it should revert with AltoBaseMarketLiquidationUnauthorized
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(USER, "");
    }

    function test_WhenPriorityLiquidationGracePeriodHasElapsed()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsTheTagger
    {
        // Skip grace period
        vm.warp(block.timestamp + market.liquidationConfiguration().priorityLiquidationGracePeriod + 1);

        deal(address(borrowToken), TAGGER, 1 ether);
        vm.startPrank(TAGGER);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), TAGGER, 0, 0, 0, 0, 0, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, "");
        vm.stopPrank();

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    modifier whenLiquidatorIsNotTheTagger() {
        _;
    }

    function test_WhenCombinedGracePeriodsHaveNotElapsed()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsNotTheTagger
    {
        // it should revert with AltoBaseMarketLiquidationUnauthorized
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(USER, "");
    }

    function test_WhenCombinedGracePeriodsHaveElapsed()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidatorIsNotTheTagger
    {
        // Skip combined grace periods
        vm.warp(
            block.timestamp + market.liquidationConfiguration().priorityLiquidationGracePeriod
                + market.liquidationConfiguration().taggerLiquidationGracePeriod + 1
        );

        deal(address(borrowToken), EXTERNAL_LIQUIDATOR, 1 ether);
        vm.startPrank(EXTERNAL_LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), EXTERNAL_LIQUIDATOR, 0, 0, 0, 0, 0, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, "");
        vm.stopPrank();

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    function test_WhenLiquidatorIsPriorityLiquidator()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
    {
        deal(address(borrowToken), PRIORITY_LIQUIDATOR, 1 ether);
        vm.startPrank(PRIORITY_LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), PRIORITY_LIQUIDATOR, 0, 0, 0, 0, 0, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, "");
        vm.stopPrank();

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    function test_WhenCurrentLTVIsAboveDisablePriorityLiquidationThreshold()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
    {
        LiquidationConfiguration memory config = market.liquidationConfiguration();
        config.disablePriorityLiquidationAbovePositionLtv = 1 ether; // if LTV is over 100%
        vm.prank(OWNER);
        market.setLiquidationConfiguration(config);

        market.accrueInterest();

        uint256 currentLtv = getCurrentLtv(USER);
        assertGt(currentLtv, market.liquidationConfiguration().disablePriorityLiquidationAbovePositionLtv);

        deal(address(borrowToken), LIQUIDATOR, 1 ether);
        vm.startPrank(LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), LIQUIDATOR, 0, 0, 0, 0, 0, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, "");
        vm.stopPrank();

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);

        // users position should be empty as we set the disablePriorityLiquidationAbovePositionLtv to 100%
        Position memory position = market.position(USER);
        assertEq(position.collateralAssets, 0);
        assertEq(position.borrowShares, 0);
    }

    function test_WhenPriorityLiquidationIsDisabled() external givenPositionIsInsolvent {
        vm.startPrank(OWNER);
        LiquidationConfiguration memory config = market.liquidationConfiguration();
        config.isEnabledPriorityLiquidation = false;
        market.setLiquidationConfiguration(config);
        vm.stopPrank();

        deal(address(borrowToken), LIQUIDATOR, 1 ether);
        vm.startPrank(LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), LIQUIDATOR, 0, 0, 0, 0, 0, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, "");
        vm.stopPrank();

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_GivenLiquidationProceeds() external {
        // it should calculate liquidation fee based on liquidator type
        // it should calculate liquidation percentage
        // it should calculate new LTV target
        // it should calculate collateral to sell
        // it should calculate final amounts
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_WhenDifferenceIsLessThanVIRTUAL_SHARES() external {
        // it should cap repay shares to user borrow shares
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_WhenDifferenceIsGreaterThanOrEqualToVIRTUAL_SHARES() external {
        // it should use calculated repay shares
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_WhenRepaySharesDoNotExceedUserBorrowShares() external {
        // it should use calculated repay shares
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_GivenLiquidationStateUpdates() external {
        // it should decrease borrower collateral assets
        // it should decrease borrower borrow shares
        // it should decrease total borrowed shares
        // it should decrease total borrowed assets
    }

    modifier givenMaxLtvPosition() {
        vm.startPrank(OWNER);
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))));
        market.setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
        vm.stopPrank();

        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), 100 ether);
        if (marketType == MarketType.BORROW) {
            market.addSupply(100 ether, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(100 ether);
            vm.stopPrank();
        }

        market.addCollateral(1 ether, USER);
        market.borrow(0.75 ether, 0, USER, USER, "");
        _;
    }

    function test_WhenPriorityLiquidationIsEnabledAndCurrentLTVIsBelowThreshold() external givenMaxLtvPosition {
        vm.startPrank(OWNER);
        LiquidationConfiguration memory config = market.liquidationConfiguration();
        config.disablePriorityLiquidationAbovePositionLtv = 0.95 ether;
        market.setLiquidationConfiguration(config);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);
        market.accrueInterest();

        uint256 currentLtv = getCurrentLtv(USER);
        assertGt(currentLtv, market.liquidationConfiguration().maxLiquidationLtv);
        assertLt(currentLtv, market.liquidationConfiguration().disablePriorityLiquidationAbovePositionLtv);

        vm.startPrank(LIQUIDATOR);
        deal(address(borrowToken), LIQUIDATOR, 1 ether);
        borrowToken.approve(address(market), 1 ether);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(USER, "");
        vm.stopPrank();

        // Tag position first
        market.tagLiquidablePosition(USER, TAGGER);
        vm.warp(block.timestamp + market.liquidationConfiguration().priorityLiquidationGracePeriod + 1);

        deal(address(borrowToken), TAGGER, 1 ether);
        vm.startPrank(TAGGER);
        borrowToken.approve(address(market), 1 ether);

        // it should delete liquidable position
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            USER, address(collateralToken), address(borrowToken), TAGGER, 0, 0, 0, 0, 0, 0, 0
        );
        market.liquidate(USER, "");
        vm.stopPrank();

        LiquidablePosition memory liquidablePosition = market.liquidablePositions(USER);
        assertFalse(liquidablePosition.tagged);
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_WhenBorrowerHasNoCollateralRemaining() external {
        // it should calculate bad debt shares
        // it should calculate bad debt assets
        // it should apply bad debt to market
        // it should reset borrower borrow shares to zero
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_WhenBorrowerHasCollateralRemaining() external {
        // it should not apply bad debt
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_GivenTokenTransfers() external {
        // it should transfer collateral tokens to liquidator
        // it should transfer borrow tokens from liquidator to market
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_WhenCallbackDataIsProvided() external {
        // it should call onLiquidateCallback
        // it should pass collateral amount and data
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_GivenEventEmission() external {
        // it should emit Liquidation event with correct parameters
    }

    /// @dev This test is covered by AltoBorrowMarket.liquidations.sol
    function test_GivenFunctionCompletion() external {
        // it should return collateral amount and repay amount
    }
}
