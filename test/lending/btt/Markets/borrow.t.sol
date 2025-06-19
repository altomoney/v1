// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {IMarketErrors, Position, IMarketEvents, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";
import {IBorrowCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract BorrowCallback is IBorrowCallback {
    event BorrowCallbackCalled();

    function onBorrowCallback(uint256, bytes calldata) external {
        emit BorrowCallbackCalled();
    }
}

contract AltoMarketBorrow is MarketCommon {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    uint256 constant INITIAL_SUPPLY = 20 ether;
    uint256 constant INITIAL_BORROWED_ASSETS = 10 ether;

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.borrow(100 ether, 0, USER, USER, "");
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.prank(PAUSER);
        market.pause(FROZEN_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.borrow(100 ether, 0, USER, USER, "");
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_BothAssetsAndSharesAreZeroOrBothNonzero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, USER, USER, "");

        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 100 ether, USER, USER, "");
    }

    function test_RevertWhen_ReceiverIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 0, USER, address(0), "");
    }

    function test_RevertWhen_SenderIsNotAuthorizedForOnBehalf() external givenInvalidInputs {
        vm.prank(USER_2);
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.borrow(100 ether, 0, USER, USER_2, "");
    }

    modifier givenValidInputs() {
        deal(address(collateralToken), address(this), 100 ether);
        deal(address(borrowToken), address(this), INITIAL_SUPPLY);
        if (marketType == MarketType.BORROW) {
            market.addSupply(INITIAL_SUPPLY, 0, SUPPLIER);
        }
        if (marketType == MarketType.MINT) {
            vm.prank(OWNER);
            AltoMintMarket(address(market)).setDebtCeiling(INITIAL_SUPPLY);
        }
        _;
    }

    function test_RevertWhen_TotalBorrowedAssetsIsGreaterThanTotalSupplyAssets() external givenValidInputs {
        market.addCollateral(20 ether, USER);

        uint256 excessiveBorrowAssets = market.totalSupply().assets + 1;
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.borrow(excessiveBorrowAssets, 0, USER, USER, "");
    }

    modifier whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets() {
        _;
    }

    function test_WhenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        market.addCollateral(20 ether, USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalSupplyAssetsBefore = market.totalSupply().assets;
        uint256 totalSupplySharesBefore = market.totalSupply().shares;
        uint256 totalBorrowedAssetsBefore = market.totalBorrowed().assets;
        uint256 totalBorrowedSharesBefore = market.totalBorrowed().shares;

        uint256 sharesToBorrow =
            INITIAL_BORROWED_ASSETS.convertToSharesUp(totalBorrowedSharesBefore, totalBorrowedAssetsBefore);

        vm.startPrank(USER);
        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);
        // it should emit Borrow event
        vm.expectEmit();
        emit IMarketEvents.Borrow(USER, USER, USER, INITIAL_BORROWED_ASSETS, sharesToBorrow, 0, 0);
        (uint256 addedAssets, uint256 addedShares, uint256 openingFeeAssets) =
            market.borrow(INITIAL_BORROWED_ASSETS, 0, USER, USER, "");
        vm.stopPrank();

        // it should return assets shares openingFeeAssets
        assertEq(addedAssets, INITIAL_BORROWED_ASSETS);
        assertEq(addedShares, sharesToBorrow);
        assertEq(openingFeeAssets, 0);

        Position memory positionAfter = market.position(USER);

        // it should update totalBorrowed and position
        assertEq(market.totalBorrowed().assets, totalBorrowedAssetsBefore + INITIAL_BORROWED_ASSETS);
        assertEq(market.totalBorrowed().shares, totalBorrowedSharesBefore + sharesToBorrow);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares + sharesToBorrow);

        // it should not update totalSupply
        assertEq(market.totalSupply().assets, totalSupplyAssetsBefore);
        assertEq(market.totalSupply().shares, totalSupplySharesBefore);

        // it should send assets minus fee to receiver
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_BORROWED_ASSETS);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_BORROWED_ASSETS);
        }
        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore);
        }

        // it should not update collateral
        assertEq(positionAfter.collateralAssets, positionBefore.collateralAssets);
    }

    function test_WhenAssetsIsZero()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        market.addCollateral(20 ether, USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalBorrowedAssetsBefore = market.totalBorrowed().assets;
        uint256 totalBorrowedSharesBefore = market.totalBorrowed().shares;

        // it should calculate assets and opening fee from shares
        uint256 sharesToBorrow =
            INITIAL_BORROWED_ASSETS.convertToSharesUp(totalBorrowedSharesBefore, totalBorrowedAssetsBefore);

        vm.startPrank(USER);
        (uint256 addedAssets, uint256 addedShares, uint256 openingFeeAssets) =
            market.borrow(0, sharesToBorrow, USER, USER, "");
        vm.stopPrank();

        // it should return assets shares openingFeeAssets
        assertEq(addedAssets, INITIAL_BORROWED_ASSETS);
        assertEq(addedShares, sharesToBorrow);
        assertEq(openingFeeAssets, 0);

        Position memory positionAfter = market.position(USER);

        // it should update totalBorrowed and position
        assertEq(market.totalBorrowed().assets, totalBorrowedAssetsBefore + INITIAL_BORROWED_ASSETS);
        assertEq(market.totalBorrowed().shares, totalBorrowedSharesBefore + sharesToBorrow);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares + sharesToBorrow);

        // it should send assets minus fee to receiver
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_BORROWED_ASSETS);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_BORROWED_ASSETS);
        }
        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore);
        }
    }

    function test_WhenSharesIsZero()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        market.addCollateral(20 ether, USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        uint256 totalBorrowedAssetsBefore = market.totalBorrowed().assets;
        uint256 totalBorrowedSharesBefore = market.totalBorrowed().shares;

        // it should calculate shares and opening fee from assets
        uint256 expectedSharesToBorrow =
            INITIAL_BORROWED_ASSETS.convertToSharesUp(totalBorrowedSharesBefore, totalBorrowedAssetsBefore);

        vm.startPrank(USER);
        (uint256 addedAssets, uint256 addedShares, uint256 openingFeeAssets) =
            market.borrow(INITIAL_BORROWED_ASSETS, 0, USER, USER, "");
        vm.stopPrank();

        // it should return assets shares openingFeeAssets
        assertEq(addedAssets, INITIAL_BORROWED_ASSETS);
        assertEq(addedShares, expectedSharesToBorrow);
        assertEq(openingFeeAssets, 0);

        Position memory positionAfter = market.position(USER);

        // it should update totalBorrowed and position
        assertEq(market.totalBorrowed().assets, totalBorrowedAssetsBefore + INITIAL_BORROWED_ASSETS);
        assertEq(market.totalBorrowed().shares, totalBorrowedSharesBefore + expectedSharesToBorrow);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares + expectedSharesToBorrow);

        // it should send assets minus fee to receiver
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_BORROWED_ASSETS);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_BORROWED_ASSETS);
        }
        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore);
        }
    }

    function test_WhenOpeningFeeIsGreaterThan0()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        uint256 openingFee = 0.05 ether;

        vm.prank(OWNER);
        market.setBorrowOpeningFee(openingFee);

        market.addCollateral(20 ether, USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();

        Position memory positionBeforeFeeRecipient = market.position(FEE_RECIPIENT);

        // it should calculate shares and opening fee from assets
        uint256 expectedOpeningFeeAssets = INITIAL_BORROWED_ASSETS.multiplyWithPrecision(openingFee);
        uint256 openingFeeShares =
            expectedOpeningFeeAssets.convertToSharesUp(totalSupplyBefore.assets, totalSupplyBefore.shares);
        uint256 expectedSharesToBorrow = (INITIAL_BORROWED_ASSETS + expectedOpeningFeeAssets).convertToSharesUp(
            totalBorrowedBefore.assets, totalBorrowedBefore.shares
        );

        vm.startPrank(USER);
        // it should emit Borrow event
        if (marketType == MarketType.BORROW) {
            vm.expectEmit();
            emit IMarketEvents.Borrow(
                USER,
                USER,
                USER,
                INITIAL_BORROWED_ASSETS,
                expectedSharesToBorrow,
                expectedOpeningFeeAssets,
                openingFeeShares
            );
        }
        if (marketType == MarketType.MINT) {
            vm.expectEmit();
            emit IMarketEvents.Borrow(
                USER, USER, USER, INITIAL_BORROWED_ASSETS, expectedSharesToBorrow, expectedOpeningFeeAssets, 0
            );
        }
        (uint256 addedAssets, uint256 addedShares, uint256 openingFeeAssets) =
            market.borrow(INITIAL_BORROWED_ASSETS, 0, USER, USER, "");
        vm.stopPrank();

        // it should return assets shares openingFeeAssets
        assertEq(addedAssets, INITIAL_BORROWED_ASSETS + expectedOpeningFeeAssets);
        assertEq(addedShares, expectedSharesToBorrow);
        assertEq(openingFeeAssets, expectedOpeningFeeAssets);

        Position memory positionAfter = market.position(USER);

        // it should update totalBorrowed and position
        assertEq(
            market.totalBorrowed().assets,
            totalBorrowedBefore.assets + INITIAL_BORROWED_ASSETS + expectedOpeningFeeAssets
        );
        assertEq(market.totalBorrowed().shares, totalBorrowedBefore.shares + expectedSharesToBorrow);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares + expectedSharesToBorrow);

        // it should send assets minus fee to receiver
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_BORROWED_ASSETS);
        if (marketType == MarketType.BORROW) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore - INITIAL_BORROWED_ASSETS);
        }
        if (marketType == MarketType.MINT) {
            assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore);
        }

        if (marketType == MarketType.BORROW) {
            // it should update totalSupply
            assertEq(market.totalSupply().assets, totalSupplyBefore.assets + expectedOpeningFeeAssets);
            assertEq(market.totalSupply().shares, totalSupplyBefore.shares + openingFeeShares);

            // it should update position
            assertEq(
                market.position(FEE_RECIPIENT).supplyShares, positionBeforeFeeRecipient.supplyShares + openingFeeShares
            );
        }

        if (marketType == MarketType.MINT) {
            // it should NOT update totalSupply
            assertEq(market.totalSupply().assets, totalSupplyBefore.assets);
            assertEq(market.totalSupply().shares, totalSupplyBefore.shares);

            // it should not update position
            assertEq(market.position(FEE_RECIPIENT).supplyShares, positionBeforeFeeRecipient.supplyShares);

            // it should update claimableFeesAssets
            assertEq(AltoMintMarket(address(market)).claimableFeesAssets(), expectedOpeningFeeAssets);
        }
    }

    function test_WhenReceiverIsAuthorizedCallbackAndDataIsNotEmpty()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        market.addCollateral(20 ether, USER);

        BorrowCallback callback = new BorrowCallback();

        vm.prank(OWNER);
        market.setAuthorizedCallback(address(callback), true);

        {
            vm.startPrank(USER);

            // it should call onBorrowCallback
            vm.expectEmit();
            emit BorrowCallback.BorrowCallbackCalled();

            market.borrow(INITIAL_BORROWED_ASSETS, 0, USER, address(callback), "some_data");
            vm.stopPrank();
        }
    }

    function test_RevertWhen_ReceiverIsNotAuthorizedCallbackAndDataIsNotEmpty()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        BorrowCallback callback = new BorrowCallback();

        market.addCollateral(20 ether, USER);

        vm.startPrank(USER);
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.borrow(INITIAL_BORROWED_ASSETS, 0, USER, address(callback), "some_data");
        vm.stopPrank();
    }

    function test_RevertWhen_PositionIsNotSolventAfterBorrow()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        market.addCollateral(1 ether, USER);

        vm.startPrank(USER);
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBorrowMarketBorrowingTooMuch.selector);
        market.borrow(2 ether, 0, USER, USER, "");
        vm.stopPrank();
    }
}
