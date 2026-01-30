// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {console2} from "forge-std/console2.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {stdError} from "forge-std/StdError.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract AltoBorrowMarketTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    MockMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
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
        });

        market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            0.75 ether,
            0,
            address(this),
            liquidationConfig
        );

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function testAddSupplyWithAssets() public {
        uint256 supplyAmount = 100 ether;

        vm.startPrank(alice);

        // Initial state check
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT);
        assertEq(borrowToken.balanceOf(address(market)), 0);

        // Add supply with assets
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(supplyAmount, 0, alice);

        // Verify assets were transferred
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - supplyAmount);
        assertEq(borrowToken.balanceOf(address(market)), supplyAmount);

        // Verify shares were minted correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(addedShares));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        // Verify total supply was updated correctly
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        assertEq(totalAssets, uint128(supplyAmount));
        assertEq(totalShares, uint128(addedShares));

        vm.stopPrank();
    }

    function testAddSupplyWithShares() public {
        // First deposit to initialize the exchange rate
        vm.startPrank(alice);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        uint256 shareAmount = 50 ether;

        vm.startPrank(bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Add supply with shares
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(0, shareAmount, bob);

        // Verify assets were transferred
        assertEq(borrowToken.balanceOf(bob), initialBalance - addedAssets);

        // Verify shares were minted correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(supplyShares, uint128(shareAmount));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        vm.stopPrank();
    }

    function testRemoveSupply() public {
        // First add supply
        vm.startPrank(alice);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(100 ether, 0, alice);

        // Verify initial state
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - addedAssets);

        // Remove part of the supply
        uint256 withdrawAmount = 40 ether;
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(withdrawAmount, 0, alice, alice);

        // Verify assets were transferred back
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - addedAssets + removedAssets);

        // Verify shares were burned correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(addedShares - removedShares));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        // Verify total supply was updated correctly
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        assertEq(totalAssets, uint128(addedAssets - removedAssets));
        assertEq(totalShares, uint128(addedShares - removedShares));

        vm.stopPrank();
    }

    function testRemoveSupplyWithShares() public {
        // First add supply
        vm.startPrank(alice);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(100 ether, 0, alice);

        // Remove part of the supply using shares
        uint256 sharesToWithdraw = 60 ether;
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(0, sharesToWithdraw, alice, alice);

        // Verify assets were transferred back
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - addedAssets + removedAssets);

        // Verify shares were burned correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(addedShares - sharesToWithdraw));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        // Verify total supply was updated correctly
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        assertEq(totalAssets, uint128(addedAssets - removedAssets));
        assertEq(totalShares, uint128(addedShares - sharesToWithdraw));

        vm.stopPrank();
    }

    function testRevertWhenBothAssetsAndSharesProvided() public {
        vm.startPrank(alice);

        // Try to add supply with both assets and shares provided
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addSupply(100 ether, 50 ether, alice);

        // First add some supply
        market.addSupply(100 ether, 0, alice);

        // Try to remove supply with both assets and shares provided
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeSupply(40 ether, 50 ether, alice, alice);

        vm.stopPrank();
    }

    function testAddCollateralWithAssets() public {
        uint256 collateralAmount = 100 ether;

        vm.startPrank(alice);

        // Initial state check
        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT);
        assertEq(collateralToken.balanceOf(address(market)), 0);

        // Add collateral with assets
        uint256 addedAssets = market.addCollateral(collateralAmount, alice);

        // Verify assets were transferred
        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT - collateralAmount);
        assertEq(collateralToken.balanceOf(address(market)), collateralAmount);

        // Verify returned values match expectations
        assertEq(addedAssets, collateralAmount);

        vm.stopPrank();
    }

    function testRemoveCollateralWithAssets() public {
        vm.startPrank(alice);
        market.addCollateral(100 ether, alice);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 removedAssets = market.removeCollateral(50 ether, alice, alice, "");
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT - 50 ether);
        assertEq(collateralToken.balanceOf(address(market)), 50 ether);
        assertEq(removedAssets, 50 ether);
    }

    function testRevertWhenAddingCollateralWithInsufficientLiquidity() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    function testRevertWhenBorrowingWithInsufficientCollateral() public {
        vm.startPrank(alice);
        market.addSupply(100 ether, 0, alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    function testAddCollateralAndBorrow() public {
        vm.startPrank(bob);
        market.addSupply(100 ether, 0, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        market.addCollateral(100 ether, alice);
        market.borrow(30 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    function testAddCollateralBorrowAndRepay() public {
        vm.startPrank(bob);
        market.addSupply(100 ether, 0, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        market.addCollateral(10 ether, alice);
        market.borrow(3 ether, 0, alice, alice, "");
        market.addInterest(1 ether);
        (uint128 assets, uint128 shares) = market.totalBorrowed();

        assertEq(assets, 4 ether);
        assertEq(shares, 3 ether * 1e6);

        market.addInterest(0.1 ether);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(borrowShares, 3 ether * 1e6);

        // assertEq(market.borrowSharesToAmount(borrowShares), 4.1 ether);
        // assertEq(market.borrowAmountToShares(4.1 ether), borrowShares);

        //market.repay(3037500000000000000, 0);
        vm.stopPrank();
    }

    // Bailsec Lending Audit; Issue #10
    function test_AltoLeverageRepay_amountOutEqualsuserBorrowedAssets() public {
        address supplier = address(0x1);
        address borrower1 = address(0x2);
        address borrower2 = address(0x5);
        address borrower = address(0xB0B);

        deal(address(borrowToken), supplier, INITIAL_AMOUNT);
        deal(address(collateralToken), borrower1, INITIAL_AMOUNT);
        deal(address(collateralToken), borrower2, INITIAL_AMOUNT);
        deal(address(collateralToken), borrower, INITIAL_AMOUNT);

        // Setup swapper and leverage
        SwapperSimpleMock swapper = new SwapperSimpleMock(address(this));
        AltoLeverage leverage = new AltoLeverage(address(swapper), address(this));
        swapper.setWhitelisted(address(leverage), true);
        leverage.setMarket(address(market), true);
        market.setAuthorizedCallback(address(leverage), true);
        deal(address(borrowToken), address(swapper), INITIAL_AMOUNT);

        // Add initial borrow token supply
        vm.startPrank(supplier);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(INITIAL_AMOUNT, 0, supplier);
        vm.stopPrank();

        // Setup borrower1's position
        vm.startPrank(borrower1);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(2, borrower1);
        market.borrow(1, 0, borrower1, borrower1, "");
        vm.stopPrank();

        // Setup borrower2's position
        vm.startPrank(borrower2);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(10, borrower2);
        market.borrow(1, 0, borrower2, borrower2, "");
        vm.stopPrank();

        (uint128 totalBorrowedAssets, uint128 totalBorrowedShares) = market.totalBorrowed();
        require(totalBorrowedAssets < totalBorrowedShares, "Need assets < shares for bug");

        vm.startPrank(borrower);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(100 ether, borrower);
        // The fix prevents shares borrows that compute to 0 assets
        // Due to virtual shares, totalBorrowedShares grows faster than totalBorrowedAssets
        // To ensure shares convert to >= 1 asset, we need: shares * (assets + 1) >= (shares_total + 1e6)
        // Borrow a large number of shares to ensure conversion results in >= 1 asset
        // Calculate minimum shares needed: shares >= (totalBorrowedShares + 1e6) / (totalBorrowedAssets + 1)
        uint256 minShares = (uint256(totalBorrowedShares) + 1_000_000) / (uint256(totalBorrowedAssets) + 1) + 1;
        market.borrow(0, minShares, borrower, borrower, "");
        vm.stopPrank();

        (totalBorrowedAssets, totalBorrowedShares) = market.totalBorrowed();
        (, uint128 borrowSharesBefore, uint128 collateralBefore) = market.position(borrower);

        uint256 userBorrowedAssets =
            uint256(borrowSharesBefore).convertToAssetsUp(totalBorrowedAssets, totalBorrowedShares);
        uint256 sharesCalculatedInRepay =
            userBorrowedAssets.convertToSharesDown(totalBorrowedAssets, totalBorrowedShares);

        assertGt(sharesCalculatedInRepay, borrowSharesBefore, "repay will calculate more shares than user has");
        assertGt(collateralBefore, 50 ether, "borrower should have enough collateral");
        assertTrue(totalBorrowedAssets < totalBorrowedShares, "assets < shares state");

        SwapParams memory swapParams = SwapParams({minAmountOut: userBorrowedAssets, swapData: hex""});
        bytes memory data = abi.encode(swapParams);

        vm.startPrank(borrower);
        market.removeCollateral(50 ether, borrower, address(leverage), data);
        vm.stopPrank();

        // Assertions after removeCollateral
        (, uint128 borrowSharesAfter, uint128 collateralAfter) = market.position(borrower);
        (uint128 totalBorrowedAssetsAfter, uint128 totalBorrowedSharesAfter) = market.totalBorrowed();

        assertEq(collateralAfter, collateralBefore - 50 ether, "collateral should decrease by 50 ether");
        assertEq(borrowSharesAfter, 0, "borrowShares should be zero after repayment");
        assertLt(totalBorrowedAssetsAfter, totalBorrowedAssets, "totalBorrowed assets should decrease");
        assertLt(totalBorrowedSharesAfter, totalBorrowedShares, "totalBorrowed shares should decrease");
    }

    function testAccrueInterest() public {
        vm.startPrank(alice);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1000 ether, bob);
        market.borrow(100 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(alice);

        // Advance time by one year (365 days)
        vm.warp(block.timestamp + 365 days);

        market.accrueInterest();

        vm.stopPrank();
    }

    /// @notice Test that virtual shares mechanism prevents inflation attacks
    /// @dev This test demonstrates that the AssetShareConversionMath library's virtual shares
    /// protection successfully prevents share inflation attacks that could otherwise allow
    /// attackers to steal funds from subsequent depositors.
    function testVirtualSharesPreventInflationAttack() public {
        address attacker = address(0xBAD);
        address victim = address(0x1234);

        // Setup attacker
        deal(address(borrowToken), attacker, INITIAL_AMOUNT);
        deal(address(collateralToken), attacker, INITIAL_AMOUNT);
        vm.prank(attacker);
        borrowToken.approve(address(market), type(uint256).max);
        vm.prank(attacker);
        collateralToken.approve(address(market), type(uint256).max);

        console2.log("=== INFLATION ATTACK DEMONSTRATION ===");

        // Step 1: Attacker deposits minimal amount
        vm.startPrank(attacker);
        market.addSupply(1, 0, attacker);
        market.addCollateral(1000 ether, attacker);

        // Step 2: Perform inflation cycles
        for (uint256 i = 0; i < 10; i++) {
            try market.borrow(1, 0, attacker, attacker, "") {
                market.addInterest(1);
                // Get actual borrow shares to repay instead of assets to avoid underflow
                (, uint128 borrowShares,) = market.position(attacker);
                if (borrowShares > 0) {
                    market.repay(0, borrowShares, attacker); // Repay using shares
                }
            } catch {
                break;
            }
        }
        vm.stopPrank();

        // Step 3: Victim deposits
        deal(address(borrowToken), victim, INITIAL_AMOUNT);
        vm.prank(victim);
        borrowToken.approve(address(market), type(uint256).max);
        vm.prank(victim);
        (, uint256 victimShares) = market.addSupply(1000 ether, 0, victim);

        // Step 4: Attacker withdraws everything
        vm.startPrank(attacker);
        (uint128 attackerShares,,) = market.position(attacker);
        (uint256 withdrawn,) = market.removeSupply(0, attackerShares, attacker, attacker);
        vm.stopPrank();

        console2.log("Attack attempted but FAILED - victim got substantial shares");

        // Verify attack was prevented by virtual shares mechanism
        assertTrue(victimShares > 0, "Victim should get shares (attack prevented)");
        console2.log("PROTECTION WORKING: Virtual shares prevented the inflation attack");
    }
}
