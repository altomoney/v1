// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";
import {IMarketErrors, Position, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

contract AltoBorrowMarketRemoveSupply is MarketCommon {
    using AssetShareConversionMath for uint256;

    uint256 internal constant INITIAL_SUPPLY = 100 ether;

    constructor() MarketCommon(MarketType.BORROW) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.removeSupply(100 ether, 0, USER, USER);
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_BothAssetsAndSharesAreZero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(0, 0, USER, USER);
    }

    function test_RevertWhen_BothAssetsAndSharesAreNon_zero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(1 ether, 1 ether, USER, USER);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(1 ether, 0, USER, address(0));
    }

    function test_RevertWhen_SenderIsNotAuthorizedForOnBehalf() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.removeSupply(1 ether, 0, USER_2, USER);
    }

    modifier givenValidInputs() {
        deal(address(borrowToken), address(this), INITIAL_SUPPLY);
        market.addSupply(INITIAL_SUPPLY, 0, USER);
        _;
    }

    function test_GivenValidInputs() external givenValidInputs {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedAssetsBefore = market.totalBorrowed().assets;
        uint256 totalBorrowedSharesBefore = market.totalBorrowed().shares;

        uint256 expectedRemovedShares =
            INITIAL_SUPPLY.convertToSharesUp(totalSupplyAssetsBefore, totalSupplySharesBefore);

        vm.startPrank(USER);
        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        // it should emit RemoveSupply event
        vm.expectEmit();
        emit IMarketEvents.RemoveSupply(USER, USER, USER, INITIAL_SUPPLY, expectedRemovedShares);
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(INITIAL_SUPPLY, 0, USER, USER);
        vm.stopPrank();

        // it should return the amount of assets and shares removed
        assertEq(removedAssets, INITIAL_SUPPLY);
        assertEq(removedShares, expectedRemovedShares);

        // it should transfer borrow tokens to receiver
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_SUPPLY);
        assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_SUPPLY);

        // it should remove supply shares from position
        assertEq(positionBefore.supplyShares - expectedRemovedShares, market.position(USER).supplyShares);
        assertEq(positionBefore.borrowShares, 0);

        // it should update totalSupply
        assertEq(totalSupplyAssetsBefore - INITIAL_SUPPLY, market.totalSupply().assets);
        assertEq(totalSupplySharesBefore - expectedRemovedShares, market.totalSupply().shares);

        // it should not update totalBorrowed
        assertEq(totalBorrowedAssetsBefore, market.totalBorrowed().assets);
        assertEq(totalBorrowedSharesBefore, market.totalBorrowed().shares);
    }

    function test_WhenAssetsIsZero() external givenValidInputs {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;

        // it should calculate assets from shares
        uint256 sharesToRemove = INITIAL_SUPPLY.convertToSharesUp(totalSupplyAssetsBefore, totalSupplySharesBefore);
        uint256 expectedRemovedAssets =
            sharesToRemove.convertToAssetsDown(totalSupplyAssetsBefore, totalSupplySharesBefore);

        vm.startPrank(USER);
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(0, sharesToRemove, USER, USER);
        vm.stopPrank();

        assertEq(removedAssets, expectedRemovedAssets);
        assertEq(removedShares, sharesToRemove);

        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_SUPPLY);
        assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_SUPPLY);

        // it should remove supply shares from position
        assertEq(positionBefore.supplyShares - sharesToRemove, market.position(USER).supplyShares);
        assertEq(positionBefore.borrowShares, 0);

        assertEq(totalSupplyAssetsBefore - INITIAL_SUPPLY, market.totalSupply().assets);
        assertEq(totalSupplySharesBefore - sharesToRemove, market.totalSupply().shares);
    }

    function test_WhenSharesIsZero() external givenValidInputs {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;

        // it should calculate shares from assets
        uint256 expectedRemovedShares =
            INITIAL_SUPPLY.convertToSharesUp(totalSupplyAssetsBefore, totalSupplySharesBefore);

        vm.startPrank(USER);
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(INITIAL_SUPPLY, 0, USER, USER);
        vm.stopPrank();

        assertEq(removedAssets, INITIAL_SUPPLY);
        assertEq(removedShares, expectedRemovedShares);

        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_SUPPLY);
        assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_SUPPLY);

        // it should remove supply shares from position
        assertEq(positionBefore.supplyShares - expectedRemovedShares, market.position(USER).supplyShares);
        assertEq(positionBefore.borrowShares, 0);

        assertEq(totalSupplyAssetsBefore - INITIAL_SUPPLY, market.totalSupply().assets);
        assertEq(totalSupplySharesBefore - expectedRemovedShares, market.totalSupply().shares);
    }
}
