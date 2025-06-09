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
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";

contract BorrowTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xCCC);
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

        // Set owner as pauser for both pause types
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPauser(owner, FROZEN_MARKET, true);

        // Setup initial balances for test accounts
        borrowToken.mint(alice, INITIAL_AMOUNT);
        borrowToken.mint(bob, INITIAL_AMOUNT);
        borrowToken.mint(charlie, INITIAL_AMOUNT);
        collateralToken.mint(alice, INITIAL_AMOUNT);
        collateralToken.mint(bob, INITIAL_AMOUNT);
        collateralToken.mint(charlie, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Add initial supply to provide liquidity
        vm.startPrank(alice);
        market.addSupply(5000 ether, 0, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() public {
        vm.startPrank(owner);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_BothAssetsAndSharesProvided() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 50 ether, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 0, bob, address(0), "");
        vm.stopPrank();
    }

    function test_RevertWhen_SenderIsNotAuthorized() public {
        vm.startPrank(charlie);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.borrow(100 ether, 0, bob, charlie, "");
        vm.stopPrank();
    }

    function test_RevertWhen_AssetsIsZero() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketHasInsufficientLiquidity() public {
        vm.startPrank(bob);
        market.addCollateral(10000 ether, bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.borrow(6000 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_UserHasInsufficientCollateral() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketBorrowingTooMuch.selector);
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_BorrowWithAssets_ZeroOpeningFee() public {
        uint256 borrowAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);
        (uint128 totalBorrowedAssetsBefore, uint128 totalBorrowedSharesBefore) = market.totalBorrowed();

        // Borrow with assets
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(borrowAmount, 0, bob, bob, "");

        // Verify assets were transferred to borrower
        assertEq(borrowToken.balanceOf(bob), initialBalance + borrowAmount);

        // Verify borrow position was created
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(borrowShares, uint128(borrowedShares));
        assertEq(collateralAssets, uint128(collateralAmount));

        // Verify total borrowed was updated
        (uint128 totalBorrowedAssetsAfter, uint128 totalBorrowedSharesAfter) = market.totalBorrowed();
        assertEq(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore + uint128(borrowedAssets));
        assertEq(totalBorrowedSharesAfter, totalBorrowedSharesBefore + uint128(borrowedShares));

        // With zero opening fee
        assertEq(openingFeeAssets, 0);

        vm.stopPrank();
    }

    function test_BorrowWithAssets_WithOpeningFee() public {
        // Set a borrow opening fee
        vm.startPrank(owner);
        market.setBorrowOpeningFee(0.01 ether); // 1% fee
        vm.stopPrank();

        uint256 borrowAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Borrow with assets
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(borrowAmount, 0, bob, bob, "");

        // Verify assets were transferred to borrower (original amount without fee)
        assertEq(borrowToken.balanceOf(bob), initialBalance + borrowAmount);

        // Verify opening fee was applied
        assertEq(openingFeeAssets, borrowAmount * 0.01 ether / 1 ether);
        assertGt(borrowedAssets, borrowAmount); // Total borrowed includes fee

        vm.stopPrank();
    }

    function test_RevertWhen_SharesIsZero() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_BorrowWithShares_ZeroOpeningFee() public {
        uint256 shareAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Borrow with shares
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(0, shareAmount, bob, bob, "");

        // Verify assets were transferred to borrower
        assertEq(borrowToken.balanceOf(bob), initialBalance + borrowedAssets);

        // Verify borrow position was created
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(borrowShares, uint128(borrowedShares));
        assertEq(collateralAssets, uint128(collateralAmount));

        // With zero opening fee
        assertEq(openingFeeAssets, 0);

        vm.stopPrank();
    }

    function test_BorrowWithShares_WithOpeningFee() public {
        // Set a borrow opening fee
        vm.startPrank(owner);
        market.setBorrowOpeningFee(0.01 ether); // 1% fee
        vm.stopPrank();

        uint256 shareAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Borrow with shares
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(0, shareAmount, bob, bob, "");

        // Verify assets were transferred to borrower (borrowedAssets minus the opening fee)
        uint256 assetsToReceiver = borrowedAssets - openingFeeAssets;
        assertEq(borrowToken.balanceOf(bob), initialBalance + assetsToReceiver);

        // Verify opening fee was applied
        assertGt(openingFeeAssets, 0);
        assertGt(borrowedShares, shareAmount); // Total shares includes fee

        vm.stopPrank();
    }
}
