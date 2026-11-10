// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketErrors, IMarketEvents, Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidablePosition,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {IAltoLiquidationEngine, LiquidationEngineInput} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";

contract LiquidateCallback is ILiquidateCallback {
    event LiquidateCallbackCalled(uint256 assetsToRepay, uint256 collateralReceived, bytes data);

    function onLiquidateCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data) external {
        emit LiquidateCallbackCalled(assetsToRepay, collateralReceived, data);
    }
}

contract AltoBorrowMarketliquidate is MarketCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    bytes32 internal constant LIQUIDATION_EVENT_SIG =
        keccak256("Liquidation(address,address,uint256,uint256,uint256,uint256,uint256,uint256)");

    address internal immutable PRIORITY_LIQUIDATOR = makeAddr("PriorityLiquidator");
    address internal immutable TAGGER = makeAddr("Tagger");
    address internal immutable EXTERNAL_LIQUIDATOR = makeAddr("ExternalLiquidator");

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function getCurrentLtv(address user) public view returns (uint256) {
        Position memory position = market.position(user);
        Balance memory totalBorrowed = market.totalBorrowed();
        uint256 collateralValue = uint256(position.collateralAssets)
            .divideWithRounding(IOracle(oracle).getPrice(), LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 positionBorrowedAssets =
            uint256(position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        return positionBorrowedAssets.divideWithPrecisionUp(collateralValue);
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.liquidate(USER, hex"", hex"");
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

        // it should revert with DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector
        );
        market.liquidate(USER, hex"", hex"");
    }

    function _fundLiquidator(address liquidator, uint256 amount) internal {
        deal(address(borrowToken), liquidator, amount);
        vm.prank(liquidator);
        borrowToken.approve(address(market), amount);
    }

    /// @dev Asserts prepareLiquidation is called with the expected liquidator and liquidationData.
    ///      Syncs interest and builds calldata before prank so static reads do not consume it.
    function _expectPrepareLiquidation(address liquidator, bytes memory liquidationData) internal {
        market.accrueInterest();

        LiquidationEngineInput memory expectedInput = LiquidationEngineInput({
            borrower: USER,
            liquidator: liquidator,
            totalSupply: market.totalSupply(),
            totalBorrowed: market.totalBorrowed(),
            position: market.position(USER),
            maxLtv: market.maxLtv(),
            collateralPrice: IOracle(oracle).getPrice(),
            liquidationData: liquidationData
        });

        vm.expectCall(
            market.liquidationEngine(),
            abi.encodeWithSelector(IAltoLiquidationEngine.prepareLiquidation.selector, expectedInput)
        );
    }

    function _assertLiquidationEventBorrowerAndLiquidator(address expectedBorrower, address expectedLiquidator)
        internal
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != LIQUIDATION_EVENT_SIG) {
                continue;
            }

            assertEq(logs[i].topics.length, 2, "Liquidation event should index borrower");
            assertEq(address(uint160(uint256(logs[i].topics[1]))), expectedBorrower, "borrower mismatch");

            address liquidator = abi.decode(logs[i].data, (address));
            assertEq(liquidator, expectedLiquidator, "originalLiquidator mismatch");

            found = true;
            break;
        }

        assertTrue(found, "Liquidation event not emitted");
    }

    function test_WhenCallerIsNotAuthorizedLiquidationPeriphery_WhenLiquidationDataIsEmpty()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
    {
        // it should pass msg.sender to liquidation engine as liquidator
        _fundLiquidator(EXTERNAL_LIQUIDATOR, 1 ether);
        _expectPrepareLiquidation(EXTERNAL_LIQUIDATOR, hex"");
        vm.prank(EXTERNAL_LIQUIDATOR);
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", hex"");

        _fundLiquidator(PRIORITY_LIQUIDATOR, 1 ether);
        _expectPrepareLiquidation(PRIORITY_LIQUIDATOR, hex"");
        vm.prank(PRIORITY_LIQUIDATOR);
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(USER, hex"", hex"");
        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
    }

    function test_WhenCallerIsNotAuthorizedLiquidationPeriphery_WhenLiquidationDataIsAbiEncodeSpoofedLiquidator()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
    {
        bytes memory spoofedLiquidationData = abi.encode(PRIORITY_LIQUIDATOR, hex"0101");

        // it should pass msg.sender to liquidation engine as liquidator
        // it should pass the full encoded bytes to liquidation engine as liquidationData
        // it should not grant priority-liquidator privileges to spoofedLiquidator
        _fundLiquidator(EXTERNAL_LIQUIDATOR, 1 ether);
        _expectPrepareLiquidation(EXTERNAL_LIQUIDATOR, spoofedLiquidationData);
        vm.prank(EXTERNAL_LIQUIDATOR);
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", spoofedLiquidationData);

        _fundLiquidator(PRIORITY_LIQUIDATOR, 1 ether);
        _expectPrepareLiquidation(PRIORITY_LIQUIDATOR, hex"");
        vm.prank(PRIORITY_LIQUIDATOR);
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(USER, hex"", hex"");
        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
    }

    function test_WhenCallerIsAuthorizedLiquidationPeriphery_WhenLiquidationDataIsNotValidAbiEncode()
        external
        givenPositionIsInsolvent
    {
        vm.prank(OWNER);
        AltoBaseMarket(address(market)).setAuthorizedLiquidationPeriphery(address(this), true);

        _fundLiquidator(address(this), 1 ether);

        // it should revert on abi.decode
        vm.expectRevert();
        market.liquidate(USER, hex"", hex"deadbeef");
    }

    function test_WhenCallerIsAuthorizedLiquidationPeriphery_WhenOriginalLiquidatorIsZeroAddress()
        external
        givenPositionIsInsolvent
    {
        vm.prank(OWNER);
        AltoBaseMarket(address(market)).setAuthorizedLiquidationPeriphery(address(this), true);

        _fundLiquidator(address(this), 1 ether);

        // it should revert with AltoBaseMarketInvalidInput
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.liquidate(USER, hex"", abi.encode(address(0), hex""));
    }

    function test_WhenCallerIsAuthorizedLiquidationPeriphery_WhenLiquidationDataIsAbiEncodeOriginalLiquidator()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
    {
        vm.prank(OWNER);
        AltoBaseMarket(address(market)).setAuthorizedLiquidationPeriphery(address(this), true);

        _fundLiquidator(address(this), 1 ether);

        bytes memory innerLiquidationData = hex"0102";

        // it should pass originalLiquidator to liquidation engine as liquidator
        // it should pass originalLiquidationData to liquidation engine as liquidationData
        // it should emit Liquidation event with originalLiquidator and borrower
        _expectPrepareLiquidation(PRIORITY_LIQUIDATOR, innerLiquidationData);

        vm.recordLogs();
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) =
            market.liquidate(USER, hex"", abi.encode(PRIORITY_LIQUIDATOR, innerLiquidationData));

        _assertLiquidationEventBorrowerAndLiquidator(USER, PRIORITY_LIQUIDATOR);

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    modifier givenPositionIsInsolvent() {
        vm.startPrank(OWNER);
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))), false);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
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
        // it should revert with DcfDlbPriorityLiquidationEngineLiquidationUnauthorized
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", hex"");
    }

    modifier whenPositionIsTagged() {
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);
        _;
    }

    function test_WhenLiquidationWindowTagHasElapsedSinceTagWasSet()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
    {
        // Advance time beyond liquidationWindowTag
        uint32 liquidationWindowTag =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration().liquidationWindowTag;
        vm.warp(block.timestamp + liquidationWindowTag + 1);

        deal(address(borrowToken), EXTERNAL_LIQUIDATOR, 1 ether);
        vm.startPrank(EXTERNAL_LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should revert with DcfDlbPriorityLiquidationEngineLiquidationUnauthorized
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", hex"");
        vm.stopPrank();
    }

    modifier whenLiquidationWindowTagHasNotElapsedSinceTagWasSet() {
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
        whenLiquidationWindowTagHasNotElapsedSinceTagWasSet
        whenLiquidatorIsTheTagger
    {
        // it should revert with DcfDlbPriorityLiquidationEngineLiquidationUnauthorized
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", hex"");
    }

    function test_WhenPriorityLiquidationGracePeriodHasElapsed()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidationWindowTagHasNotElapsedSinceTagWasSet
        whenLiquidatorIsTheTagger
    {
        // Skip grace period but ensure we don't exceed liquidationWindowTag
        LiquidationConfiguration memory config =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        uint32 priorityLiquidationGracePeriod = config.priorityLiquidationGracePeriod;
        uint32 liquidationWindowTag = config.liquidationWindowTag;
        // Advance time by grace period, but ensure we're still within liquidationWindowTag
        uint256 timeToAdvance = priorityLiquidationGracePeriod + 1;
        require(timeToAdvance < liquidationWindowTag, "Grace period exceeds liquidationWindowTag");
        vm.warp(block.timestamp + timeToAdvance);

        deal(address(borrowToken), TAGGER, 1 ether);
        vm.startPrank(TAGGER);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, TAGGER, 0, 0, 0, 0, 0, 0);
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
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
        whenLiquidationWindowTagHasNotElapsedSinceTagWasSet
        whenLiquidatorIsNotTheTagger
    {
        // it should revert with DcfDlbPriorityLiquidationEngineLiquidationUnauthorized
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", hex"");
    }

    function test_WhenCombinedGracePeriodsHaveElapsed()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
        whenLiquidatorIsNotPriorityLiquidator
        whenPositionIsTagged
        whenLiquidationWindowTagHasNotElapsedSinceTagWasSet
        whenLiquidatorIsNotTheTagger
    {
        // Skip combined grace periods but ensure we don't exceed liquidationWindowTag
        LiquidationConfiguration memory config =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        uint32 priorityLiquidationGracePeriod = config.priorityLiquidationGracePeriod;
        uint32 taggerLiquidationGracePeriod = config.taggerLiquidationGracePeriod;
        uint32 liquidationWindowTag = config.liquidationWindowTag;
        // Advance time by combined grace periods, but ensure we're still within liquidationWindowTag
        uint256 timeToAdvance = priorityLiquidationGracePeriod + taggerLiquidationGracePeriod + 1;
        require(timeToAdvance < liquidationWindowTag, "Combined grace periods exceed liquidationWindowTag");
        vm.warp(block.timestamp + timeToAdvance);

        deal(address(borrowToken), EXTERNAL_LIQUIDATOR, 1 ether);
        vm.startPrank(EXTERNAL_LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, EXTERNAL_LIQUIDATOR, 0, 0, 0, 0, 0, 0);
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
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
        emit IMarketEvents.Liquidation(USER, PRIORITY_LIQUIDATOR, 0, 0, 0, 0, 0, 0);
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
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
        LiquidationConfiguration memory config = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .liquidationConfiguration();
        config.disablePriorityLiquidationAbovePositionLtv = 1 ether; // if LTV is over 100%
        vm.startPrank(OWNER);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(config);
        vm.stopPrank();

        market.accrueInterest();

        uint256 currentLtv = getCurrentLtv(USER);
        assertGt(
            currentLtv,
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .liquidationConfiguration()
            .disablePriorityLiquidationAbovePositionLtv
        );

        deal(address(borrowToken), LIQUIDATOR, 1 ether);
        vm.startPrank(LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, LIQUIDATOR, 0, 0, 0, 0, 0, 0);
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
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
        LiquidationConfiguration memory config =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        config.isEnabledPriorityLiquidation = false;
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(config);
        vm.stopPrank();

        deal(address(borrowToken), LIQUIDATOR, 1 ether);
        vm.startPrank(LIQUIDATOR);
        borrowToken.approve(address(market), 1 ether);

        // it should proceed with liquidation
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, LIQUIDATOR, 0, 0, 0, 0, 0, 0);
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");
        vm.stopPrank();

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    modifier givenMaxLtvPosition() {
        vm.startPrank(OWNER);
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))), false);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(PRIORITY_LIQUIDATOR, true);
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
        LiquidationConfiguration memory config =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        config.disablePriorityLiquidationAbovePositionLtv = 0.95 ether;
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(config);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);
        market.accrueInterest();

        LiquidationConfiguration memory configAfter =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        uint256 currentLtv = getCurrentLtv(USER);
        assertGt(currentLtv, configAfter.maxLiquidationLtv);
        assertLt(currentLtv, configAfter.disablePriorityLiquidationAbovePositionLtv);

        vm.startPrank(LIQUIDATOR);
        deal(address(borrowToken), LIQUIDATOR, 1 ether);
        borrowToken.approve(address(market), 1 ether);
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(USER, hex"", hex"");
        vm.stopPrank();

        // Tag position first
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(USER, TAGGER);
        vm.warp(
            block.timestamp
                + IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
                .liquidationConfiguration()
                .priorityLiquidationGracePeriod + 1
        );

        deal(address(borrowToken), TAGGER, 1 ether);
        vm.startPrank(TAGGER);
        borrowToken.approve(address(market), 1 ether);

        // it should delete liquidable position
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(USER, TAGGER, 0, 0, 0, 0, 0, 0);
        market.liquidate(USER, hex"", hex"");
        vm.stopPrank();

        LiquidablePosition memory liquidablePosition =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidablePositions(USER);
        assertFalse(liquidablePosition.tagged);
    }

    function test_GivenEventEmission_WhenDirectLiquidator()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
    {
        _fundLiquidator(PRIORITY_LIQUIDATOR, 1 ether);

        vm.recordLogs();
        vm.prank(PRIORITY_LIQUIDATOR);
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) = market.liquidate(USER, hex"", hex"");

        _assertLiquidationEventBorrowerAndLiquidator(USER, PRIORITY_LIQUIDATOR);

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }

    function test_GivenEventEmission_WhenAuthorizedPeripheryForwardsOriginalLiquidator()
        external
        givenPositionIsInsolvent
        whenPriorityLiquidationIsEnabled
        whenCurrentLTVIsBelowDisablePriorityLiquidationThreshold
    {
        vm.prank(OWNER);
        AltoBaseMarket(address(market)).setAuthorizedLiquidationPeriphery(address(this), true);

        _fundLiquidator(address(this), 1 ether);

        bytes memory innerLiquidationData = hex"0102";

        vm.recordLogs();
        (uint256 collateralAmount, uint256 repayAmount, uint256 protocolFee) =
            market.liquidate(USER, hex"", abi.encode(PRIORITY_LIQUIDATOR, innerLiquidationData));

        _assertLiquidationEventBorrowerAndLiquidator(USER, PRIORITY_LIQUIDATOR);

        assertGt(collateralAmount, 0);
        assertGt(repayAmount, 0);
        assertGt(protocolFee, 0);
    }
}
