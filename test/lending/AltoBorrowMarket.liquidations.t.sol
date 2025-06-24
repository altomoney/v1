// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarket, IMarketEvents, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";

contract LiquidateCallback is ILiquidateCallback {
    function onLiquidateCallback(uint256 assets, bytes calldata data) external {
        (address borrowToken, uint256 borrowAmount) = abi.decode(data, (address, uint256));
        IERC20(borrowToken).approve(msg.sender, borrowAmount);
    }
}

contract AltoBorrowMarketTest is Test {
    using AssetShareConversionMath for uint256;

    MockMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    LiquidateCallback liquidateCallback;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address liquidator = address(0xC0C);
    address taggerLiquidator = address(0xD0D);
    address externalLiquidator = address(0xE0E);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function createMarket(
        LiquidationConfiguration memory liquidationConfiguration,
        uint256 collateralPrice,
        uint256 maxLtv
    ) public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(collateralPrice);

        market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            maxLtv,
            0,
            address(this),
            liquidationConfiguration
        );

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        //deal(address(borrowToken), charlie, INITIAL_AMOUNT);
        deal(address(borrowToken), taggerLiquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), externalLiquidator, INITIAL_AMOUNT);

        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        //deal(address(collateralToken), charlie, INITIAL_AMOUNT);
        deal(address(collateralToken), taggerLiquidator, INITIAL_AMOUNT);
        deal(address(collateralToken), externalLiquidator, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(externalLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(market.owner());
        market.setPriorityLiquidator(bob, true);
        market.setPriorityLiquidator(liquidator, true);
        market.setPriorityLiquidator(address(liquidateCallback), true);
        vm.stopPrank();
    }

    function setUp() public {
        liquidateCallback = new LiquidateCallback();
    }

    uint256 internal constant VIRTUAL_SHARES = 1e6;

    /// @dev A number of virtual assets of 1 enforces a conversion rate between shares and assets when a market is
    /// empty.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivUp(shares, totalAssets + 1, totalShares + VIRTUAL_SHARES);
    }

    function testLiquidate() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            1e35,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(10 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        deal(address(borrowToken), liquidator, 0.625 ether);
        vm.startPrank(liquidator);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.32 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 0.82 ether);

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);

        assertEq(currentLtv, 0.82 ether);
        assertEq(newLtv, 0.6 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            6.75 ether,
            0.625 ether,
            market.borrowAmountToShares(0.625 ether),
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 6.75 ether);
        assertEq(repayAmount, 0.625 ether);

        vm.stopPrank();
    }

    function testFullLiquidate() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            2 * ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(1 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 1 ether);
        market.addInterest(2 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 3 ether - 1);

        vm.stopPrank();

        deal(address(borrowToken), liquidator, 1.9 ether);
        vm.startPrank(liquidator);

        uint256 borrowSharesToRepay = market.borrowAmountToShares(1.9 ether);
        uint256 badDebtShares = IMarket(address(market)).position(bob).borrowShares - borrowSharesToRepay;
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            1 ether,
            1.9 ether,
            borrowSharesToRepay,
            1.1 ether - 1,
            badDebtShares
        );

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);
        assertEq(currentLtv, 1.5 ether);
        assertEq(newLtv, 0 ether);

        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 1 ether);
        assertEq(repayAmount, 1.9 ether);

        (uint128 assets, uint128 shares) = market.totalBorrowed();
        assertEq(assets, 1);
        assertEq(shares, 0 ether);

        assertEq(collateralToken.balanceOf(liquidator), 1 ether);
        assertEq(borrowToken.balanceOf(liquidator), 0);

        vm.stopPrank();
    }

    function testLiquidateAtLltv() public {
        LiquidationConfiguration memory liquidationConfiguration = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        createMarket(liquidationConfiguration, ORACLE_PRICE_PRECISION, 0.75 ether);

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.3 ether);
        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.8 ether);
        vm.stopPrank();

        deal(address(borrowToken), externalLiquidator, 0.453044162158624307 ether);
        vm.startPrank(externalLiquidator);

        market.tagLiquidablePosition(bob, externalLiquidator);

        vm.warp(
            block.timestamp + IMarket(address(market)).liquidationConfiguration().priorityLiquidationGracePeriod + 1
        );

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);

        assertEq(currentLtv, 0.8 ether);
        assertEq(newLtv, 0.7125 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            externalLiquidator,
            0.513044009445403087 ether,
            0.453044162158624307 ether,
            283152493245491393478263,
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 0.513044009445403087 ether);
        assertEq(repayAmount, 0.453044162158624307 ether);

        assertApproxEqAbs(
            collateralAmount - repayAmount,
            // because we have deposited 1 ether worth of collateral, we dont have apply percentage to it
            liquidationConfiguration.dynamicBonusFeeStart + liquidationConfiguration.liquidationBaseFee,
            0.0001 ether
        );

        vm.stopPrank();
    }

    function testLiquidateAtTlltv() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();

        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);
        vm.stopPrank();

        deal(address(borrowToken), liquidator, 0.9 ether);
        vm.startPrank(liquidator);
        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);

        assertEq(currentLtv, 0.9 ether);
        assertEq(newLtv, 0);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob, address(collateralToken), address(borrowToken), liquidator, 0.95 ether, 0.9 ether, 500000 ether, 0, 0
        );

        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 0.95 ether);
        assertEq(repayAmount, 0.9 ether);

        vm.stopPrank();
    }

    function testTagPosition() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertTrue(tagged);
        assertEq(tagger, taggerLiquidator);
        assertEq(timestamp, block.timestamp);
    }

    function testLiquidateTaggedPositionAsTagger() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration = IMarket(address(market)).liquidationConfiguration();

        vm.warp(block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod + 1);
        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            taggerLiquidator,
            950000343607371433,
            900000343607371433,
            500000 ether,
            0,
            0
        );
        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 950000343607371433);
        assertEq(repayAmount, 900000343607371433);

        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertFalse(tagged);
        assertEq(tagger, address(0));
        assertEq(timestamp, 0);
    }

    function testLiquidateTaggedPositionAsExternalLiquidator() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration = IMarket(address(market)).liquidationConfiguration();

        vm.warp(
            block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod
                + liquidationConfiguration.taggerLiquidationGracePeriod + 1
        );
        vm.startPrank(externalLiquidator);
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            externalLiquidator,
            950000480593735489,
            900000480593735489,
            500000 ether,
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 950000480593735489);
        assertEq(repayAmount, 900000480593735489);

        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertFalse(tagged);
        assertEq(tagger, address(0));
        assertEq(timestamp, 0);
    }

    function testLiquidateAsPriorityLiquidator() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        deal(address(borrowToken), liquidator, 0.9 ether);
        vm.startPrank(liquidator);
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob, address(collateralToken), address(borrowToken), liquidator, 0.95 ether, 0.9 ether, borrowShares, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 0.95 ether);
        assertEq(repayAmount, 0.9 ether);

        vm.stopPrank();
    }

    function testLiquidateHealthyPositionShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup healthy position (low LTV)
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.3 ether, 0, bob, bob, ""); // Low LTV position
        vm.stopPrank();

        // Try to liquidate as priority liquidator
        vm.startPrank(liquidator);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidatingSolventPosition.selector);
        market.liquidate(bob, hex"");
        vm.stopPrank();
    }

    function testLiquidateUntaggedPositionAsNonPriorityShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether); // Make position underwater
        vm.stopPrank();

        // Try to liquidate as non-priority liquidator
        vm.startPrank(externalLiquidator);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, hex"");
        vm.stopPrank();
    }

    function testLiquidateBeforeGracePeriodAsTaggerShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether);
        vm.stopPrank();

        // Tag position
        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);

        // Try to liquidate immediately (before grace period)
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, hex"");
        vm.stopPrank();
    }

    function testLiquidateBeforeGracePeriodAsExternalShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether);
        vm.stopPrank();

        // Tag position
        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        // Warp past priority grace period but before tagger grace period
        vm.warp(block.timestamp + 6 minutes); // 5 minutes priority + 1 minute (before 2 minutes tagger period)

        // Try to liquidate as external liquidator
        vm.startPrank(externalLiquidator);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, hex"");
        vm.stopPrank();
    }

    function testReTagPositionShouldBePossibleAfterTagWindow() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        market.addInterest(0.4 ether);

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        vm.warp(block.timestamp + IMarket(address(market)).liquidationConfiguration().liquidationWindowTag + 1);

        vm.startPrank(alice);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, alice, block.timestamp);
        market.tagLiquidablePosition(bob, alice);
        vm.stopPrank();
    }

    function testReTagPositionShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        market.addInterest(0.4 ether);

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationAlreadyTagged.selector);
        market.tagLiquidablePosition(bob, alice);
        vm.stopPrank();
    }

    function testFullLiquidateBadDebt() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(2 ether, bob);
        market.borrow(1 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 1 ether);
        market.addInterest(2 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 3 ether - 1);

        vm.stopPrank();

        vm.startPrank(liquidator);
        deal(address(borrowToken), liquidator, 1.9 ether);

        uint256 borrowSharesToRepay = market.borrowAmountToShares(1.9 ether);
        uint256 badDebtShares = IMarket(address(market)).position(bob).borrowShares - borrowSharesToRepay;
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            2 ether,
            1.9 ether,
            borrowSharesToRepay,
            1.1 ether - 1,
            badDebtShares
        );

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);
        assertEq(currentLtv, 1.5 ether);
        assertEq(newLtv, 0 ether);

        (uint256 collateralAmount, uint256 repayAmount) = market.liquidate(bob, hex"");

        assertEq(collateralAmount, 2 ether);
        assertEq(repayAmount, 1.9 ether);

        (uint128 assets, uint128 shares) = market.totalBorrowed();
        assertEq(assets, 1);
        assertEq(shares, 0 ether);

        assertEq(IMarket(address(market)).position(bob).collateralAssets, 0);
        assertEq(IMarket(address(market)).position(bob).borrowShares, 0);

        assertEq(collateralToken.balanceOf(liquidator), 2 ether);
        assertEq(borrowToken.balanceOf(liquidator), 0);

        vm.stopPrank();
    }

    function testLiquidateWithCallback() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            1e35,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(10 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.32 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 0.82 ether);

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);

        assertEq(currentLtv, 0.82 ether);
        assertEq(newLtv, 0.6 ether);

        deal(address(borrowToken), address(liquidateCallback), 0.625 ether);
        vm.startPrank(address(liquidateCallback));

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            address(liquidateCallback),
            6.75 ether,
            0.625 ether,
            market.borrowAmountToShares(0.625 ether),
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount) =
            market.liquidate(bob, abi.encode(address(borrowToken), 0.625 ether));

        assertEq(collateralAmount, 6.75 ether);
        assertEq(repayAmount, 0.625 ether);

        vm.stopPrank();
    }
}
