// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMarketErrors, IMarketEvents, Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract AltoMarketRepay is MarketCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    uint256 constant INITIAL_SUPPLY = 100 ether;
    uint256 constant REPAY_AMOUNT = 5 ether;

    constructor(MarketType marketType) MarketCommon(marketType) {}

    using SafeERC20 for IERC20;

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.repay(100 ether, 0, USER);
    }

    modifier givenInvalidInput() {
        _;
    }

    function test_RevertWhen_BothAssetsAndSharesAreZeroOrBothNonzero() external givenInvalidInput {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(0, 0, USER);

        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(100 ether, 100 ether, USER);
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external givenInvalidInput {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(100 ether, 0, address(0));
    }

    modifier givenValidInput() {
        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), INITIAL_SUPPLY);
        if (marketType == MarketType.BORROW) {
            market.addSupply(INITIAL_SUPPLY, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(INITIAL_SUPPLY);
        }

        market.addCollateral(10 ether, USER);
        market.borrow(5 ether, 0, USER, USER, "");
        _;
    }

    function test_GivenValidInput() external givenValidInput {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();
        Position memory positionBefore = market.position(USER);

        uint256 sharesToRepay = REPAY_AMOUNT.convertToSharesDown(totalBorrowedBefore.assets, totalBorrowedBefore.shares);

        vm.startPrank(USER);
        if (marketType == MarketType.BORROW) {
            borrowToken.approve(address(market), REPAY_AMOUNT);
        }
        // it should accrue interest
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        // it should emit Repay event
        vm.expectEmit();
        emit IMarketEvents.Repay(USER, USER, REPAY_AMOUNT, sharesToRepay);
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(REPAY_AMOUNT, 0, USER);
        vm.stopPrank();

        // it should return assets and shares
        assertEq(repaidAssets, REPAY_AMOUNT);
        assertEq(repaidShares, sharesToRepay);

        // it should update totalBorrowed
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore.assets - REPAY_AMOUNT);
        assertEq(market.totalBorrowed().shares, totalBorrowedBefore.shares - sharesToRepay);

        // it should not update totalSupply
        assertEq(market.totalSupply().assets, totalSupplyBefore.assets);
        assertEq(market.totalSupply().shares, totalSupplyBefore.shares);

        // it should update onBehalf's position borrowShares and nothing else
        assertEq(market.position(USER).borrowShares, positionBefore.borrowShares - sharesToRepay);
        assertEq(market.position(USER).supplyShares, positionBefore.supplyShares);

        // it should transfer assets from msg.sender to contract
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore - REPAY_AMOUNT);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore + REPAY_AMOUNT);
        }

        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore);
        }
    }

    function test_WhenAssetsIsZero() external givenValidInput {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Position memory positionBefore = market.position(USER);

        // it should calculate assets from shares
        uint256 sharesToRepay = REPAY_AMOUNT.convertToSharesDown(totalBorrowedBefore.assets, totalBorrowedBefore.shares);

        vm.startPrank(USER);
        if (marketType == MarketType.BORROW) {
            borrowToken.approve(address(market), REPAY_AMOUNT);
        }
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(REPAY_AMOUNT, 0, USER);
        vm.stopPrank();

        // it should return assets and shares
        assertEq(repaidAssets, REPAY_AMOUNT);
        assertEq(repaidShares, sharesToRepay);

        // it should update totalBorrowed
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore.assets - REPAY_AMOUNT);
        assertEq(market.totalBorrowed().shares, totalBorrowedBefore.shares - sharesToRepay);

        // it should update onBehalf's position borrowShares and nothing else
        assertEq(market.position(USER).borrowShares, positionBefore.borrowShares - sharesToRepay);
        assertEq(market.position(USER).supplyShares, positionBefore.supplyShares);

        // it should transfer assets from msg.sender to contract
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore - REPAY_AMOUNT);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore + REPAY_AMOUNT);
        }

        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), 0);
        }
    }

    function test_WhenSharesIsZero() external givenValidInput {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Position memory positionBefore = market.position(USER);

        // it should calculate shares from assets
        uint256 sharesToRepay = REPAY_AMOUNT.convertToSharesDown(totalBorrowedBefore.assets, totalBorrowedBefore.shares);

        vm.startPrank(USER);
        if (marketType == MarketType.BORROW) {
            borrowToken.approve(address(market), REPAY_AMOUNT);
        }
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(0, sharesToRepay, USER);
        vm.stopPrank();

        // it should return assets and shares
        assertEq(repaidAssets, REPAY_AMOUNT);
        assertEq(repaidShares, sharesToRepay);

        // it should update totalBorrowed
        assertEq(market.totalBorrowed().assets, totalBorrowedBefore.assets - REPAY_AMOUNT);
        assertEq(market.totalBorrowed().shares, totalBorrowedBefore.shares - sharesToRepay);

        // it should update onBehalf's position borrowShares and nothing else
        assertEq(market.position(USER).borrowShares, positionBefore.borrowShares - sharesToRepay);
        assertEq(market.position(USER).supplyShares, positionBefore.supplyShares);

        // it should transfer assets from msg.sender to contract
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore - REPAY_AMOUNT);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore + REPAY_AMOUNT);
        }

        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), 0);
        }
    }
}
