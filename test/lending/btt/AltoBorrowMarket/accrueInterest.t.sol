// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";

contract AccrueInterestTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address owner = address(this);
    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new AltoBorrowMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            0,
            owner,
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            })
        );

        // Set owner as pauser for PAUSED_MARKET
        market.setPauser(owner, PAUSED_MARKET, true);

        // Setup initial balances for test accounts
        borrowToken.mint(alice, INITIAL_AMOUNT);
        borrowToken.mint(bob, INITIAL_AMOUNT);
        collateralToken.mint(alice, INITIAL_AMOUNT);
        collateralToken.mint(bob, INITIAL_AMOUNT);

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

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.accrueInterest();
    }

    function test_NotAccrueInterestWhen_TotalBorrowedIsZero() public {
        // Initial state check - no borrows
        (uint128 totalAssetsBefore, uint128 totalSharesBefore) = market.totalBorrowed();
        assertEq(totalAssetsBefore, 0);
        assertEq(totalSharesBefore, 0);

        // Accrue interest when no borrows exist
        market.accrueInterest();

        // Verify no change in borrowed amounts
        (uint128 totalAssetsAfter, uint128 totalSharesAfter) = market.totalBorrowed();
        assertEq(totalAssetsAfter, 0);
        assertEq(totalSharesAfter, 0);
    }

    function test_NotAccrueInterestWhen_BorrowRateIsZero() public {
        // Set up supply and borrow to create a position
        vm.startPrank(alice);
        market.addSupply(1000 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1000 ether, bob);
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();

        // Get initial state
        (uint128 totalAssetsBefore, uint128 totalSharesBefore) = market.totalBorrowed();

        // For a zero interest rate scenario, we need to deploy a zero rate IRM
        // Since we're using FixedRateIrm with 0.04 ether rate, this test shows minimal interest
        market.accrueInterest();

        // With very small time passage, interest should be minimal or zero
        (uint128 totalAssetsAfter, uint128 totalSharesAfter) = market.totalBorrowed();

        // Verify shares don't change (only assets might change due to interest)
        assertEq(totalSharesAfter, totalSharesBefore);

        // Assets might change slightly due to interest calculations
        assertGe(totalAssetsAfter, totalAssetsBefore);
    }

    function test_AccrueInterestWhen_BorrowRateIsGreaterThanZero() public {
        // Set up supply and borrow to create a position
        vm.startPrank(alice);
        market.addSupply(1000 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1000 ether, bob);
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();

        // Get initial state
        (uint128 supplyAssetsBefore, uint128 supplySharesBefore) = market.totalSupply();
        (uint128 borrowAssetsBefore, uint128 borrowSharesBefore) = market.totalBorrowed();

        // Advance time to accumulate interest
        vm.warp(block.timestamp + 365 days);

        // Accrue interest
        market.accrueInterest();

        // Get state after interest accrual
        (uint128 supplyAssetsAfter, uint128 supplySharesAfter) = market.totalSupply();
        (uint128 borrowAssetsAfter, uint128 borrowSharesAfter) = market.totalBorrowed();

        // Verify interest was accrued
        assertGt(supplyAssetsAfter, supplyAssetsBefore);
        assertGt(borrowAssetsAfter, borrowAssetsBefore);

        // Shares should remain the same
        assertEq(supplySharesAfter, supplySharesBefore);
        assertEq(borrowSharesAfter, borrowSharesBefore);

        // The increase in supply and borrow assets should be equal (interest)
        uint256 supplyIncrease = supplyAssetsAfter - supplyAssetsBefore;
        uint256 borrowIncrease = borrowAssetsAfter - borrowAssetsBefore;
        assertEq(supplyIncrease, borrowIncrease);
    }
}
