// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarket, IMarketEvents, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {console} from "forge-std/console.sol";
import {stdError} from "forge-std/StdError.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AltoLiquidationEngine} from "@alto/lending/AltoLiquidationEngine.sol";
import {
    IPriorityLiquidationEngine,
    IPriorityLiquidationEngineEvents,
    IPriorityLiquidationEngineStaticTypes,
    IPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";

contract LiquidateCallback is ILiquidateCallback {
    function onLiquidateCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data) external {
        (address borrowToken, uint256 borrowAmount) = abi.decode(data, (address, uint256));
        IERC20(borrowToken).approve(msg.sender, assetsToRepay);
    }
}

contract AltoBorrowMarketTest is Test {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    MockMarket market;
    IMarket internal imarket;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    LiquidateCallback liquidateCallback;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address liquidator = address(0xC0C);
    address taggerLiquidator = address(0xD0D);
    address externalLiquidator = address(0xE0E);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    address internal immutable FEE_RECEIVER = makeAddr("FeeReceiver");

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

        // Create liquidation engine before market deployment
        address liquidationEngine = address(new AltoLiquidationEngine(address(this)));

        market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            maxLtv,
            0,
            FEE_RECEIVER,
            liquidationConfiguration,
            liquidationEngine
        );

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        IPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfiguration);

        imarket = IMarket(address(market));

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        //deal(address(borrowToken), charlie, INITIAL_AMOUNT);
        deal(address(borrowToken), taggerLiquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), externalLiquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), market.owner(), INITIAL_AMOUNT);

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
        IPriorityLiquidationEngine(liquidationEngine).setPriorityLiquidator(bob, true);
        IPriorityLiquidationEngine(liquidationEngine).setPriorityLiquidator(liquidator, true);
        IPriorityLiquidationEngine(liquidationEngine).setPriorityLiquidator(address(liquidateCallback), true);
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

    function testLiquidationRevertForSmallPosition() public {
        // deploying market with collateral price of 1e30
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                protocolFeePercentage: 0.075 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            1e30,
            0.75 ether
        );

        vm.startPrank(bob);
        // adding 1e8 collateral
        market.addCollateral(1e8, bob);
        // creating a borrowing position
        market.borrow(10, 0, bob, bob, "");
        vm.stopPrank();

        // adding interest to make position underwater
        market.addInterest(0.32 ether);

        // updating oracle price to 1e27 so that (price * amount) < 1e36. So, positionCollateralValue will round down to 0
        // hence liquidation will revert
        OracleMock(market.oracle()).setPrice(1e27);

        (,, uint128 collateralAssets) = market.position(bob);

        console.log(
            "Position Collateral Value",
            uint256(collateralAssets)
                .divideWithRounding(OracleMock(market.oracle()).getPrice(), LENDING_ORACLE_PRICE_PRECISION, false)
        );

        vm.expectRevert(stdError.divisionError);
        market.liquidate(bob, hex"", hex"");

        vm.startPrank(market.owner());
        market.governanceLiquidate(bob);
    }

    function testGovernanceLiquidateSuccessWithSocializingDebt() public {
        // deploying market with collateral price of 1e30
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                protocolFeePercentage: 0.075 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            1e30,
            0.75 ether
        );

        vm.startPrank(bob);
        // adding 1e8 collateral
        market.addCollateral(1e8, bob);
        // creating a borrowing position
        market.borrow(10, 0, bob, bob, "");
        vm.stopPrank();

        // updating oracle price to 1e27 so that (price * amount) < 1e36. So, positionCollateralValue will round down to 0
        // hence liquidation will revert
        OracleMock(market.oracle()).setPrice(1e27);

        (, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);

        console.log(
            "Position Collateral Value",
            uint256(collateralAssets)
                .divideWithRounding(OracleMock(market.oracle()).getPrice(), LENDING_ORACLE_PRICE_PRECISION, false)
        );

        // attempt governance liquidation with socializing debt
        vm.startPrank(market.owner());
        borrowToken.approve(address(market), type(uint256).max);
        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(market.owner());
        (uint128 totalSupplyAssetsBefore, uint128 totalSupplySharesBefore) = market.totalSupply();
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.GovernanceLiquidation(
            bob, address(collateralToken), address(borrowToken), market.owner(), 1e8, 10, borrowShares
        );
        market.governanceLiquidate(bob);
        vm.stopPrank();

        (, borrowShares, collateralAssets) = market.position(bob);

        (uint128 totalSupplyAssetsAfter, uint128 totalSupplySharesAfter) = market.totalSupply();
        (uint128 totalBorrowedAssetsAfter, uint128 totalBorrowedSharesAfter) = market.totalBorrowed();

        // total supply assets is reduced by the amount of debt repaid
        assertEq(totalSupplySharesAfter, totalSupplySharesBefore);
        assertEq(totalSupplyAssetsAfter, totalSupplyAssetsBefore - 10);

        // total borrowed is zero since full debt is repaid
        assertEq(totalBorrowedSharesAfter, 0);
        assertEq(totalBorrowedAssetsAfter, 0);

        // borrow token balance of owner is unchanged since debt is socialized
        assertEq(borrowToken.balanceOf(market.owner()), borrowTokenBalanceBefore);

        // collateral assets are zero since full collateral is seized
        assertEq(collateralAssets, 0);
        assertEq(borrowShares, 0);
    }

    function testBadDebtLiquidationWithDonationAttack() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        // bob supplies 2 ether as collateral
        market.addCollateral(2 ether, bob);
        // bob borrows 1.5 ether
        market.borrow(1.5 ether, 0, bob, bob, "");
        vm.stopPrank();

        vm.startPrank(alice);
        // alice donates 1.5 ether to the market
        borrowToken.transfer(address(market), 1.5 ether);
        // alice can't remove full supply because of bob's borrowing
        // invariant prevents donation of borrow assets and removing supply
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.removeSupply(100 ether, 0, alice, alice);
        vm.stopPrank();

        uint256 newOraclePrice = 1e30;
        // update oracle price to 1e30 to make bob's position underwater
        OracleMock(market.oracle()).setPrice(newOraclePrice);

        vm.startPrank(liquidator);
        // liquidator has 2 ether of borrow tokens
        deal(address(borrowToken), liquidator, 2 ether);

        (,, uint128 collateralAssets) = market.position(bob);
        (uint128 totalBorrowedAssets,) = market.totalBorrowed();

        uint256 collateralValue =
            uint256(collateralAssets).divideWithRounding(newOraclePrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 borrowValue = totalBorrowedAssets;

        // bad debt has been created for bob's position
        assertGt(borrowValue, collateralValue, "bad debt has not been created yet");

        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            2 ether,
            0,
            1900000000000,
            1.9 ether,
            1499998100000000000,
            1499998100000000000000000
        );
        market.liquidate(bob, hex"", hex"");

        vm.stopPrank();
    }

    function testLiquidatorCanReceiveFeeWithoutRepayingDebt() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            0.0003e36,
            0.75 ether
        );

        // Initial User position:
        // collateralAssets = 10525 wei
        //  collateralValue = 3 wei
        //  borrowAssets = 2 wei

        vm.startPrank(bob);
        // bob supplies 10525 assets
        market.addCollateral(10525, bob);
        // bob borrows 2 wei of assets
        market.borrow(2 wei, 0, bob, bob, "");
        vm.stopPrank();

        // After price goes down:
        // collateralPrice = 0.0001e36
        // collateralValue = 1 wei
        OracleMock(market.oracle()).setPrice(0.0001e36);

        uint256 collateralBalanceOfLiqudatorBefore = collateralToken.balanceOf(liquidator);
        uint256 debtBalanceOfLiqudatorBefore = borrowToken.balanceOf(liquidator);

        // After liquidation:
        // liquidationBaseFee = 0.05e18
        // liquidationPercentage = 1e18
        // newLtv = 0

        // liquidatorBonusFee = 526
        // remainingCollateralAfterFee = 10_525 - 526 = 9999 wei
        // remainingCollateralAfterFeeInBorrowAssets = 0 wei (truncation)
        // collateralToSellInBorrowAssets = 2 wei --> clamped to 0 wei

        // totalCollateralToTake = 526 wei (only liquidation fee)
        // repayAmount = 0
        vm.startPrank(liquidator);
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();

        uint256 collateralBalanceOfLiqudatorAfter = collateralToken.balanceOf(liquidator);
        uint256 debtBalanceOfLiqudatorAfter = borrowToken.balanceOf(liquidator);
        assertGt(
            collateralBalanceOfLiqudatorAfter,
            collateralBalanceOfLiqudatorBefore,
            "liquidator did not receive collateral after first liquidation"
        );
        assertEq(
            debtBalanceOfLiqudatorAfter,
            debtBalanceOfLiqudatorBefore,
            "liquidator paid debt which is not needed after first liquidation"
        );

        vm.prank(bob);
        market.addCollateral(1, bob);

        collateralBalanceOfLiqudatorBefore = collateralToken.balanceOf(liquidator);
        debtBalanceOfLiqudatorBefore = borrowToken.balanceOf(liquidator);
        vm.startPrank(liquidator);
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();

        collateralBalanceOfLiqudatorAfter = collateralToken.balanceOf(liquidator);
        debtBalanceOfLiqudatorAfter = borrowToken.balanceOf(liquidator);
        assertGt(
            collateralBalanceOfLiqudatorAfter,
            collateralBalanceOfLiqudatorBefore,
            "liquidator did not receive collateral after second liquidation"
        );
        assertEq(
            debtBalanceOfLiqudatorAfter,
            debtBalanceOfLiqudatorBefore,
            "liquidator paid debt which is not needed after second liquidation"
        );
    }

    function testLiquidateBasic() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                protocolFeePercentage: 0.075 ether,
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

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);
        assertEq(liquidatorFee, 0.5 ether);
        assertEq(protocolFee, 0.0375 ether);

        uint256 expectedCollateralAmount = 6.75 ether;
        uint256 expectedRepayAmount = 0.625 ether;

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            expectedCollateralAmount,
            protocolFee,
            expectedRepayAmount,
            market.borrowAmountToShares(expectedRepayAmount),
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, expectedCollateralAmount);
        assertEq(repayAmount, expectedRepayAmount);
        assertEq(returnedProtocolFee, protocolFee);

        assertEq(imarket.position(FEE_RECEIVER).collateralAssets, protocolFee);
        assertEq(collateralToken.balanceOf(address(market)), 10 ether - expectedCollateralAmount + protocolFee);

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
                protocolFeePercentage: 0.075 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            2 * LENDING_ORACLE_PRICE_PRECISION,
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

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);
        assertEq(liquidatorFee, 0.05 ether);
        assertEq(protocolFee, 0.00375 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            1 ether,
            protocolFee,
            1.9 ether,
            borrowSharesToRepay,
            1.1 ether - 1,
            badDebtShares
        );

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);
        assertEq(currentLtv, 1.5 ether);
        assertEq(newLtv, 0 ether);

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 1 ether);
        assertEq(repayAmount, 1.9 ether);
        assertEq(returnedProtocolFee, protocolFee);

        (uint128 assets, uint128 shares) = market.totalBorrowed();
        assertEq(assets, 1);
        assertEq(shares, 0 ether);

        assertEq(collateralToken.balanceOf(liquidator), 1 ether - protocolFee);
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
            protocolFeePercentage: 0 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        createMarket(liquidationConfiguration, LENDING_ORACLE_PRICE_PRECISION, 0.75 ether);

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

        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, externalLiquidator);

        vm.warp(
            block.timestamp
                + IPriorityLiquidationEngine(market.liquidationEngine())
                .liquidationConfiguration()
                .priorityLiquidationGracePeriod + 1
        );

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);

        assertEq(currentLtv, 0.8 ether);
        assertEq(newLtv, 0.7125 ether);

        market.accrueInterest();

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, false);
        assertEq(liquidatorFee, 0.05999984728677878 ether);
        assertEq(protocolFee, 0);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            externalLiquidator,
            0.513044009445403087 ether,
            protocolFee,
            0.453044162158624307 ether,
            283152493245491393478263,
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 0.513044009445403087 ether);
        assertEq(repayAmount, 0.453044162158624307 ether);
        assertEq(returnedProtocolFee, protocolFee);

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
                protocolFeePercentage: 0.075 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, false);
        assertEq(liquidatorFee, 0.05 ether);
        assertEq(protocolFee, 0.00375 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            0.95 ether,
            protocolFee,
            0.9 ether,
            500000 ether,
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 0.95 ether);
        assertEq(repayAmount, 0.9 ether);
        assertEq(returnedProtocolFee, protocolFee);

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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) =
            IPriorityLiquidationEngineStaticTypes(market.liquidationEngine()).liquidablePositions(bob);
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
                protocolFeePercentage: 0.075 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();

        vm.warp(block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod + 1);
        vm.startPrank(taggerLiquidator);

        market.accrueInterest();
        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, false);
        assertEq(liquidatorFee, 0.05 ether);
        assertEq(protocolFee, 0.00375 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            taggerLiquidator,
            950000343607371433,
            protocolFee,
            900000343607371433,
            500000 ether,
            0,
            0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 950000343607371433);
        assertEq(repayAmount, 900000343607371433);
        assertEq(returnedProtocolFee, protocolFee);

        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) =
            IPriorityLiquidationEngineStaticTypes(market.liquidationEngine()).liquidablePositions(bob);
        assertFalse(tagged);
        assertEq(tagger, address(0));
        assertEq(timestamp, 0);

        assertEq(imarket.position(FEE_RECEIVER).collateralAssets, protocolFee);
        assertEq(collateralToken.balanceOf(address(market)), 1 ether - 0.950000343607371433 ether + protocolFee);
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
                protocolFeePercentage: 0.075 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();

        vm.warp(
            block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod
                + liquidationConfiguration.taggerLiquidationGracePeriod + 1
        );
        vm.startPrank(externalLiquidator);

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, false);
        assertEq(liquidatorFee, 0.05 ether);
        assertEq(protocolFee, 0.00375 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            externalLiquidator,
            950000480593735489,
            protocolFee,
            900000480593735489,
            500000 ether,
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 950000480593735489);
        assertEq(repayAmount, 900000480593735489);

        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) =
            IPriorityLiquidationEngineStaticTypes(market.liquidationEngine()).liquidablePositions(bob);
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);
        assertEq(liquidatorFee, 0.05 ether);
        assertEq(protocolFee, 0);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            0.95 ether,
            protocolFee,
            0.9 ether,
            borrowShares,
            0,
            0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 0.95 ether);
        assertEq(repayAmount, 0.9 ether);
        assertEq(returnedProtocolFee, protocolFee);

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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup healthy position (low LTV)
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.3 ether, 0, bob, bob, ""); // Low LTV position
        vm.stopPrank();

        // Try to liquidate as priority liquidator
        vm.startPrank(liquidator);
        vm.expectRevert(
            IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidatingSolventPosition.selector
        );
        market.liquidate(bob, hex"", hex"");
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        vm.expectRevert(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidationUnauthorized.selector);
        market.liquidate(bob, hex"", hex"");
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);

        // Try to liquidate immediately (before grace period)
        vm.expectRevert(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidationUnauthorized.selector);
        market.liquidate(bob, hex"", hex"");
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        // Warp past priority grace period but before tagger grace period
        vm.warp(block.timestamp + 6 minutes); // 5 minutes priority + 1 minute (before 2 minutes tagger period)

        // Try to liquidate as external liquidator
        vm.startPrank(externalLiquidator);
        vm.expectRevert(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidationUnauthorized.selector);
        market.liquidate(bob, hex"", hex"");
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        vm.warp(
            block.timestamp
                + IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration().liquidationWindowTag
                + 1
        );

        vm.startPrank(alice);
        vm.expectEmit();
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, alice, block.timestamp);
        IPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, alice);
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        market.addInterest(0.4 ether);

        IPriorityLiquidationEngine liquidationEngine = IPriorityLiquidationEngine(market.liquidationEngine());

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        liquidationEngine.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IPriorityLiquidationEngineErrors.AltoPriorityLiquidationEngineLiquidationAlreadyTagged.selector);
        liquidationEngine.tagLiquidablePosition(bob, alice);
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
                protocolFeePercentage: 0 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            LENDING_ORACLE_PRICE_PRECISION,
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

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);
        assertEq(liquidatorFee, 0.1 ether);
        assertEq(protocolFee, 0);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            liquidator,
            2 ether,
            protocolFee,
            1.9 ether,
            borrowSharesToRepay,
            1.1 ether - 1,
            badDebtShares
        );

        (uint256 currentLtv, uint256 newLtv) = market.calculatePreLiquidationLtv(bob);
        assertEq(currentLtv, 1.5 ether);
        assertEq(newLtv, 0 ether);

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 2 ether);
        assertEq(repayAmount, 1.9 ether);
        assertEq(returnedProtocolFee, protocolFee);

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
                protocolFeePercentage: 0.075 ether,
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

        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);
        assertEq(liquidatorFee, 0.5 ether);
        assertEq(protocolFee, 0.0375 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            address(liquidateCallback),
            6.75 ether,
            protocolFee,
            0.625 ether,
            market.borrowAmountToShares(0.625 ether),
            0,
            0
        );

        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, abi.encode(address(borrowToken), 0.625 ether), hex"");

        assertEq(collateralAmount, 6.75 ether);
        assertEq(repayAmount, 0.625 ether);
        assertEq(returnedProtocolFee, protocolFee);

        assertEq(imarket.position(FEE_RECEIVER).collateralAssets, protocolFee);
        assertEq(collateralToken.balanceOf(address(market)), 10 ether - 6.75 ether + protocolFee);

        vm.stopPrank();
    }
}
