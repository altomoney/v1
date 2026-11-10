// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketErrors, Position, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

contract AltoBorrowMarketRemoveSupply is MarketCommon {
    using AssetShareConversionMath for uint256;

    uint256 internal constant INITIAL_SUPPLY = 100 ether;

    constructor() MarketCommon(MarketType.BORROW) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.removeSupply(100 ether, 0, USER, USER);
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_BothAssetsAndSharesAreZero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeSupply(0, 0, USER, USER);
    }

    function test_RevertWhen_BothAssetsAndSharesAreNon_zero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeSupply(1 ether, 1 ether, USER, USER);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeSupply(1 ether, 0, USER, address(0));
    }

    function test_RevertWhen_SenderIsNotAuthorizedForOnBehalf() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
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

    function test_RevertWhen_RemovingSupplyCausesInsufficientMarketLiquidity() external {
        // given: USER supplies and someone borrows all available liquidity
        uint256 supplyAmount = INITIAL_SUPPLY;
        deal(address(borrowToken), address(this), supplyAmount);
        market.addSupply(supplyAmount, 0, USER);

        // prepare sufficient collateral for USER_2 to borrow full supply
        uint256 collateralAmount = 200 ether; // enough for LTV 0.75 to borrow 100 ether
        deal(address(collateralToken), USER_2, collateralAmount);
        vm.startPrank(USER_2);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(collateralAmount, USER_2);
        uint256 borrowable = market.totalSupply().assets;
        // borrow exactly total supply so totalBorrowed == totalSupply
        market.borrow(borrowable, 0, USER_2, USER_2, "");
        vm.stopPrank();

        // when: USER tries to remove any positive amount of supply
        vm.startPrank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.removeSupply(1, 0, USER, USER);
        vm.stopPrank();
    }
}
