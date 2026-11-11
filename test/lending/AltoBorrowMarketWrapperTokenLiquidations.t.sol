// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {WrapperTokenHarness} from "./btt/WrapperTokens/WrapperToken/mocks/WrapperTokenHarness.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarket, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineEvents,
    IDcfDlbPriorityLiquidationEngineStaticTypes,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract LiquidateCallback is ILiquidateCallback {
    function onLiquidateCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data) external {
        (address borrowToken, uint256 borrowAmount) = abi.decode(data, (address, uint256));
        IERC20(borrowToken).approve(msg.sender, assetsToRepay);
    }
}

/// @dev Liquidation tests for `WrapperToken` collateral. Scenarios identical to
///      `AltoBorrowMarket.liquidations.t.sol` are omitted; only tests that verify wrapper balances remain.
contract AltoBorrowMarketWrapperTokenLiquidationsTest is Test {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    MockMarket market;
    IMarket internal imarket;
    ERC20Mock borrowToken;
    ERC20Mock underlyingPt;
    WrapperTokenHarness wrapper;

    LiquidateCallback liquidateCallback;

    uint256 internal constant WRAPPER_EXCHANGE_RATE = 1.25e18;
    uint8 internal constant TOKEN_DECIMALS = 18;

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
        underlyingPt = new ERC20Mock("Underlying PT", "UPT");
        wrapper = new WrapperTokenHarness("Wrapped PT", "wPT", address(underlyingPt), address(this), address(this));
        wrapper.setExchangeRateForTest(WRAPPER_EXCHANGE_RATE);

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(collateralPrice);

        market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(wrapper),
            address(irm),
            address(this),
            address(oracle),
            maxLtv,
            0,
            FEE_RECEIVER,
            liquidationConfiguration
        );

        imarket = IMarket(address(market));

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        //deal(address(borrowToken), charlie, INITIAL_AMOUNT);
        deal(address(borrowToken), taggerLiquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), externalLiquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), market.owner(), INITIAL_AMOUNT);

        _fundWrappedCollateral(alice, INITIAL_AMOUNT);
        _fundWrappedCollateral(bob, INITIAL_AMOUNT);
        _fundWrappedCollateral(taggerLiquidator, INITIAL_AMOUNT);
        _fundWrappedCollateral(externalLiquidator, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(externalLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(market.owner());
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(bob, true);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(liquidator, true);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .setPriorityLiquidator(address(liquidateCallback), true);
        vm.stopPrank();
    }

    function setUp() public {
        liquidateCallback = new LiquidateCallback();
        assertGt(WRAPPER_EXCHANGE_RATE, 1e18, "wrapper exchange rate should exceed par");
    }

    function _fundWrappedCollateral(address user, uint256 wrappedAmount) internal {
        uint256 ptAmount = Math.ceilDiv(wrappedAmount * 10 ** TOKEN_DECIMALS, WRAPPER_EXCHANGE_RATE);
        deal(address(underlyingPt), user, ptAmount);

        vm.startPrank(user);
        underlyingPt.approve(address(wrapper), ptAmount);
        wrapper.wrap(ptAmount);
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

        uint256 collateralBalanceOfLiqudatorBefore = wrapper.balanceOf(liquidator);
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

        uint256 collateralBalanceOfLiqudatorAfter = wrapper.balanceOf(liquidator);
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

        collateralBalanceOfLiqudatorBefore = wrapper.balanceOf(liquidator);
        debtBalanceOfLiqudatorBefore = borrowToken.balanceOf(liquidator);
        vm.startPrank(liquidator);
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();

        collateralBalanceOfLiqudatorAfter = wrapper.balanceOf(liquidator);
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
        assertEq(wrapper.balanceOf(address(market)), 10 ether - expectedCollateralAmount + protocolFee);

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
            bob, liquidator, 1 ether, protocolFee, 1.9 ether, borrowSharesToRepay, 1.1 ether - 1, badDebtShares
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

        assertEq(wrapper.balanceOf(liquidator), 1 ether - protocolFee);
        assertEq(borrowToken.balanceOf(liquidator), 0);

        vm.stopPrank();
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
        emit IDcfDlbPriorityLiquidationEngineEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();

        vm.warp(block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod + 1);
        vm.startPrank(taggerLiquidator);

        market.accrueInterest();
        (uint256 liquidatorFee, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, false);
        assertEq(liquidatorFee, 0.05 ether);
        assertEq(protocolFee, 0.00375 ether);

        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob, taggerLiquidator, 950000343607371433, protocolFee, 900000343607371433, 500000 ether, 0, 0
        );
        (uint256 collateralAmount, uint256 repayAmount, uint256 returnedProtocolFee) =
            market.liquidate(bob, hex"", hex"");

        assertEq(collateralAmount, 950000343607371433);
        assertEq(repayAmount, 900000343607371433);
        assertEq(returnedProtocolFee, protocolFee);

        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) =
            IDcfDlbPriorityLiquidationEngineStaticTypes(market.liquidationEngine()).liquidablePositions(bob);
        assertFalse(tagged);
        assertEq(tagger, address(0));
        assertEq(timestamp, 0);

        assertEq(imarket.position(FEE_RECEIVER).collateralAssets, protocolFee);
        assertEq(wrapper.balanceOf(address(market)), 1 ether - 0.950000343607371433 ether + protocolFee);
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
            bob, liquidator, 2 ether, protocolFee, 1.9 ether, borrowSharesToRepay, 1.1 ether - 1, badDebtShares
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

        assertEq(wrapper.balanceOf(liquidator), 2 ether);
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
        assertEq(wrapper.balanceOf(address(market)), 10 ether - 6.75 ether + protocolFee);

        vm.stopPrank();
    }
}
