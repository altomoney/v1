// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {IMarket, Balance, Position} from "@alto/lending/interfaces/IMarket.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {console} from "forge-std/console.sol";
import {stdError} from "forge-std/StdError.sol";

contract AltoBorrowMarketLiquidationUnderflowTest is Test {
    MockMarket market;
    IMarket internal imarket;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    address alice = address(0xA111CE);
    address bob = address(0xB0B);
    address borrower1 = address(0xB0B1);
    address borrower2 = address(0xB0B2);
    address liquidator = address(0xC0C);
    address supplier = address(0xD0D);
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

        market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken),
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
        deal(address(borrowToken), liquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), borrower1, INITIAL_AMOUNT);
        deal(address(borrowToken), borrower2, INITIAL_AMOUNT);
        deal(address(borrowToken), supplier, INITIAL_AMOUNT);

        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), borrower1, INITIAL_AMOUNT);
        deal(address(collateralToken), borrower2, INITIAL_AMOUNT);
        deal(address(collateralToken), supplier, INITIAL_AMOUNT);

        // // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addSupply(1 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower1);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower2);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(supplier);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(market.owner());
        market.setPriorityLiquidator(bob, true);
        market.setPriorityLiquidator(liquidator, true);
        vm.stopPrank();

        vm.startPrank(supplier);
        market.addSupply(INITIAL_AMOUNT, 0, supplier);
        vm.stopPrank();
    }

    function setUp() public {
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
                disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            1e36, // 1 USD
            0.75 ether // 75% LTV
        );
    }

    function testLiquidationUnderflowWhenBorrowAssetsMoreThanBorrowShares() public {
        (uint128 borrowAssets, uint128 borrowShares) = market.totalBorrowed();
        console.log("Borrow assets before interest:", borrowAssets);
        console.log("Borrow shares before interest:", borrowShares);

        // Configure totalBorrowed so that (shares + 1e6) / (assets + 1) == 3 exactly
        // Mint two borrow shares (assets remain ~0 initially due to rounding)
        vm.startPrank(borrower1);
        market.addCollateral(2, borrower1);
        market.borrow(0, 1, borrower1, borrower1, "");
        vm.stopPrank();

        (borrowAssets, borrowShares) = market.totalBorrowed();
        console.log("Borrow assets after first borrow:", borrowAssets);
        console.log("Borrow shares after first borrow:", borrowShares);

        vm.startPrank(borrower2);
        market.addCollateral(10, borrower2);
        market.borrow(0, 1, borrower2, borrower2, "");
        vm.stopPrank();

        (borrowAssets, borrowShares) = market.totalBorrowed();
        console.log("Borrow assets after second borrow:", borrowAssets);
        console.log("Borrow shares after second borrow:", borrowShares);

        // Set totalBorrowed.assets to 333,333 so ratio becomes 3
        market.addInterest(333_333);

        (borrowAssets, borrowShares) = market.totalBorrowed();
        console.log("Borrow assets after interest:", borrowAssets);
        console.log("Borrow shares after interest:", borrowShares);

        // Make borrower2 insolvent
        OracleMock(market.oracle()).setPrice(1e36 / 10);

        vm.startPrank(liquidator);

        (, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(borrower2, true);

        // Check only indexed topic (user); data fields are dynamic and computed on-chain
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            borrower2, address(collateralToken), address(borrowToken), liquidator, 0, 0, 0, 0, 0, 0, 0
        );

        (,, uint128 feeRecipientCollateralBefore) = market.position(FEE_RECEIVER);
        (, uint128 borrowerBorrowSharesBefore,) = market.position(borrower2);

        market.liquidate(borrower2, "");

        (,, uint128 feeRecipientCollateralAfter) = market.position(FEE_RECEIVER);
        (, uint128 borrowerBorrowSharesAfter,) = market.position(borrower2);

        // Protocol fee should be credited to fee recipient's collateral
        assertEq(
            uint256(feeRecipientCollateralAfter),
            uint256(feeRecipientCollateralBefore) + protocolFee,
            "Protocol fee should be credited"
        );
        // Borrower debt should decrease
        assertLt(
            borrowerBorrowSharesAfter, borrowerBorrowSharesBefore, "Borrower debt should decrease after liquidation"
        );
        vm.stopPrank();
    }

    function testLiquidationWhenBorrowSharesMoreThanBorrowAssets() public {
        (uint128 borrowAssets, uint128 borrowShares) = market.totalBorrowed();
        console.log("Borrow assets before interest:", borrowAssets);
        console.log("Borrow shares before interest:", borrowShares);

        vm.startPrank(borrower1);
        market.addCollateral(2, borrower1);
        market.borrow(1, 0, borrower1, borrower1, "");
        vm.stopPrank();

        (borrowAssets, borrowShares) = market.totalBorrowed();
        console.log("Borrow assets after first borrow:", borrowAssets);
        console.log("Borrow shares after first borrow:", borrowShares);

        vm.startPrank(borrower2);
        market.addCollateral(10, borrower2);
        market.borrow(1, 0, borrower2, borrower2, "");
        vm.stopPrank();

        (borrowAssets, borrowShares) = market.totalBorrowed();
        console.log("Borrow assets after second borrow:", borrowAssets);
        console.log("Borrow shares after second borrow:", borrowShares);

        (borrowAssets, borrowShares) = market.totalBorrowed();
        console.log("Borrow assets after interest:", borrowAssets);
        console.log("Borrow shares after interest:", borrowShares);

        // Make borrower2 insolvent
        OracleMock(market.oracle()).setPrice(1e36 / 10);

        vm.startPrank(liquidator);

        (, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(borrower2, true);

        // Check only indexed topic (user); data fields are dynamic and computed on-chain
        vm.expectEmit(true, false, false, false);
        emit IMarketEvents.Liquidation(
            borrower2, address(collateralToken), address(borrowToken), liquidator, 0, 0, 0, 0, 0, 0, 0
        );

        (,, uint128 feeRecipientCollateralBefore) = market.position(FEE_RECEIVER);
        (, uint128 borrowerBorrowSharesBefore,) = market.position(borrower2);

        market.liquidate(borrower2, "");

        (,, uint128 feeRecipientCollateralAfter) = market.position(FEE_RECEIVER);
        (, uint128 borrowerBorrowSharesAfter,) = market.position(borrower2);

        // Protocol fee should be credited to fee recipient's collateral
        assertEq(
            uint256(feeRecipientCollateralAfter),
            uint256(feeRecipientCollateralBefore) + protocolFee,
            "Protocol fee should be credited"
        );
        // Borrower debt should decrease
        assertLt(
            borrowerBorrowSharesAfter, borrowerBorrowSharesBefore, "Borrower debt should decrease after liquidation"
        );
        vm.stopPrank();
    }
}
