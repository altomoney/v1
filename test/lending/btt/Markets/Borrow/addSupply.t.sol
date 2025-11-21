// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarketErrors, Position, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

contract AltoBorrowMarketAddSupply is MarketCommon {
    using AssetShareConversionMath for uint256;

    uint256 internal constant INITIAL_SUPPLY = 100 ether;

    constructor() MarketCommon(MarketType.BORROW) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.addSupply(100 ether, 0, USER);
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.prank(PAUSER);
        market.pause(FROZEN_TYPE, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        market.addSupply(100 ether, 0, USER);
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_BothAssetsAndSharesAreZero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addSupply(0, 0, USER);
    }

    function test_RevertWhen_BothAssetsAndSharesAreNon_zero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addSupply(1 ether, 1 ether, USER);
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addSupply(1 ether, 0, address(0));
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_UserHasInsufficientBalance() external givenValidInputs {
        uint256 excessiveAmount = borrowToken.balanceOf(USER) + 1;

        vm.startPrank(USER);
        borrowToken.approve(address(market), excessiveAmount);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, USER, borrowToken.balanceOf(USER), excessiveAmount
            )
        );
        market.addSupply(excessiveAmount, 0, USER);
        vm.stopPrank();
    }

    modifier whenUserHasSufficientBalance() {
        deal(address(borrowToken), USER, INITIAL_SUPPLY);
        _;
    }

    function test_WhenUserHasSufficientBalance() external givenValidInputs whenUserHasSufficientBalance {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedAssetsBefore = market.totalBorrowed().assets;
        uint256 totalBorrowedSharesBefore = market.totalBorrowed().shares;

        uint256 expectedAddedShares =
            INITIAL_SUPPLY.convertToSharesDown(totalSupplyAssetsBefore, totalSupplySharesBefore);

        vm.startPrank(USER);
        borrowToken.approve(address(market), INITIAL_SUPPLY);
        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        // it should emit AddSupply event
        vm.expectEmit();
        emit IMarketEvents.AddSupply(USER, USER, INITIAL_SUPPLY, expectedAddedShares);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(INITIAL_SUPPLY, 0, USER);
        vm.stopPrank();

        // it should transfer borrow tokens from sender
        assertEq(userBalanceBefore - INITIAL_SUPPLY, borrowToken.balanceOf(USER));
        assertEq(marketBalanceBefore + INITIAL_SUPPLY, borrowToken.balanceOf(address(market)));

        // it should return the amount of assets and shares added
        assertEq(addedAssets, INITIAL_SUPPLY);
        assertEq(addedShares, expectedAddedShares, "addedShares");

        // it should add supply shares to position
        assertEq(positionBefore.supplyShares + expectedAddedShares, market.position(USER).supplyShares);
        assertEq(positionBefore.borrowShares, 0);

        // it should update totalSupply
        assertEq(totalSupplyAssetsBefore + INITIAL_SUPPLY, market.totalSupply().assets);
        assertEq(totalSupplySharesBefore + expectedAddedShares, market.totalSupply().shares);

        // it should not update totalBorrowed
        assertEq(totalBorrowedAssetsBefore, market.totalBorrowed().assets);
        assertEq(totalBorrowedSharesBefore, market.totalBorrowed().shares);
    }

    function test_WhenAssetsIsZero() external givenValidInputs whenUserHasSufficientBalance {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;

        // it should calculate assets from shares
        uint256 sharesToAdd = INITIAL_SUPPLY.convertToSharesDown(totalSupplyAssetsBefore, totalSupplySharesBefore);
        uint256 expectedAddedAssets = sharesToAdd.convertToAssetsUp(totalSupplyAssetsBefore, totalSupplySharesBefore);

        vm.startPrank(USER);
        borrowToken.approve(address(market), INITIAL_SUPPLY);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(0, sharesToAdd, USER);
        vm.stopPrank();

        assertEq(addedAssets, expectedAddedAssets);
        assertEq(addedShares, sharesToAdd);

        assertEq(borrowToken.balanceOf(USER), userBalanceBefore - expectedAddedAssets);
        assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore + expectedAddedAssets);

        // it should add supply shares to position
        assertEq(positionBefore.supplyShares + addedShares, market.position(USER).supplyShares);
        assertEq(positionBefore.borrowShares, 0);

        assertEq(totalSupplyAssetsBefore + expectedAddedAssets, market.totalSupply().assets);
        assertEq(totalSupplySharesBefore + addedShares, market.totalSupply().shares);
    }

    function test_WhenSharesIsZero() external givenValidInputs whenUserHasSufficientBalance {
        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;

        // it should calculate shares from assets
        uint256 expectedAddedShares =
            INITIAL_SUPPLY.convertToSharesDown(totalSupplyAssetsBefore, totalSupplySharesBefore);

        vm.startPrank(USER);
        borrowToken.approve(address(market), INITIAL_SUPPLY);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(INITIAL_SUPPLY, 0, USER);
        vm.stopPrank();

        assertEq(addedAssets, INITIAL_SUPPLY);
        assertEq(addedShares, expectedAddedShares);

        assertEq(borrowToken.balanceOf(USER), userBalanceBefore - INITIAL_SUPPLY);
        assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore + INITIAL_SUPPLY);

        /// it should add supply shares to position
        assertEq(positionBefore.supplyShares + addedShares, market.position(USER).supplyShares);
        assertEq(positionBefore.borrowShares, 0);

        assertEq(totalSupplyAssetsBefore + INITIAL_SUPPLY, market.totalSupply().assets);
        assertEq(totalSupplySharesBefore + addedShares, market.totalSupply().shares);
    }

    function test_RevertWhen_SupplyCapIsExceeded() external givenValidInputs whenUserHasSufficientBalance {
        // Set a supply cap that will be exceeded
        uint128 supplyCap = 200 ether;
        vm.prank(OWNER);
        AltoBorrowMarket(address(market)).setSupplyCap(supplyCap);

        // First, supply some amount to get close to the cap
        uint256 firstSupply = 150 ether;
        deal(address(borrowToken), SUPPLIER, firstSupply);
        vm.startPrank(SUPPLIER);
        borrowToken.approve(address(market), firstSupply);
        market.addSupply(firstSupply, 0, SUPPLIER);
        vm.stopPrank();

        // Now try to supply more that would exceed the cap
        uint256 currentSupply = market.totalSupply().assets;
        uint256 excessAmount = supplyCap - currentSupply + 1 ether; // This will exceed the cap

        deal(address(borrowToken), USER, excessAmount);
        vm.startPrank(USER);
        borrowToken.approve(address(market), excessAmount);
        // it should revert
        vm.expectRevert(AltoBorrowMarket.AltoBorrowMarketSupplyCapExceeded.selector);
        market.addSupply(excessAmount, 0, USER);
        vm.stopPrank();
    }
}
