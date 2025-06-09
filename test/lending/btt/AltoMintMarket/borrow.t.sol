// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";

contract MockCallback {
    function onBorrowCallback(uint256 amount, bytes calldata data) external {}
}

contract BorrowTest is AltoMintMarketTest {
    MockCallback internal callback;

    function setUp() public override {
        super.setUp();
        callback = new MockCallback();

        // Set owner as pauser for both pause types
        vm.startPrank(owner);
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPauser(owner, FROZEN_MARKET, true);
        market.setAuthorizedCallback(address(callback), true);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.startPrank(owner);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_BothAssetsAndSharesProvided() external {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 50 ether, alice, alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_ReceiverIsZeroAddress() external {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 0, alice, address(0), "");
        vm.stopPrank();
    }

    function test_RevertWhen_SenderIsNotAuthorized() external {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.borrow(100 ether, 0, alice, bob, "");
        vm.stopPrank();
    }

    modifier givenAssetsIsProvided() {
        _;
    }

    function test_RevertWhen_AssetsIsZero() external givenAssetsIsProvided {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, alice, alice, "");
        vm.stopPrank();
    }

    modifier whenAssetsIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_BorrowAmountExceedsDebtCeiling()
        external
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
    {
        // Give alice enough collateral
        deal(address(collateralToken), alice, DEBT_CEILING * 3);
        vm.startPrank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(DEBT_CEILING * 2, alice);

        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.borrow(DEBT_CEILING + 1 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_UserHasInsufficientCollateral()
        external
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
    {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketBorrowingTooMuch.selector);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();
    }

    modifier whenUserHasSufficientCollateral() {
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice);
        vm.stopPrank();
        _;
    }

    function test_MintTokensAndUpdatePositionWhen_BorrowOpeningFeeIsZero()
        external
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
        whenUserHasSufficientCollateral
    {
        // Set up with zero opening fee
        vm.prank(owner);
        market.setBorrowOpeningFee(0);

        uint256 borrowAmount = 100 ether;
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();
        (, uint128 borrowSharesBefore,) = market.position(alice);

        vm.startPrank(alice);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) = market.borrow(borrowAmount, 0, alice, alice, "");
        vm.stopPrank();

        // it should mint tokens and update position
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + borrowAmount);
        assertEq(openingFeeAssets, 0);

        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);

        (, uint128 borrowSharesAfter,) = market.position(alice);
        assertGt(borrowSharesAfter, borrowSharesBefore);
    }

    function test_MintTokensAndUpdatePositionAndApplyFeeWhen_BorrowOpeningFeeIsGreaterThanZero()
        external
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
        whenUserHasSufficientCollateral
    {
        uint256 borrowAmount = 100 ether;
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();
        (, uint128 borrowSharesBefore,) = market.position(alice);

        vm.startPrank(alice);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) = market.borrow(borrowAmount, 0, alice, alice, "");
        vm.stopPrank();

        // it should mint tokens, update position and apply fee
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + borrowAmount);
        assertGt(openingFeeAssets, 0);

        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);

        (, uint128 borrowSharesAfter,) = market.position(alice);
        assertGt(borrowSharesAfter, borrowSharesBefore);
    }

    modifier givenSharesIsProvided() {
        _;
    }

    function test_RevertWhen_SharesIsZero() external givenSharesIsProvided {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, alice, alice, "");
        vm.stopPrank();
    }

    modifier whenSharesIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_SharesBorrowAmountExceedsDebtCeiling()
        external
        givenSharesIsProvided
        whenSharesIsGreaterThanZero
    {
        // Give alice enough collateral
        deal(address(collateralToken), alice, DEBT_CEILING * 3);
        vm.startPrank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(DEBT_CEILING * 2, alice);

        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.borrow(0, DEBT_CEILING + 1 ether, alice, alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_SharesUserHasInsufficientCollateral()
        external
        givenSharesIsProvided
        whenSharesIsGreaterThanZero
    {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketBorrowingTooMuch.selector);
        market.borrow(0, 100 ether, alice, alice, "");
        vm.stopPrank();
    }

    modifier whenSharesUserHasSufficientCollateral() {
        vm.startPrank(alice);
        // Increase collateral significantly for shares-based borrowing
        // Shares can result in much larger asset amounts due to conversion
        market.addCollateral(5000 ether, alice);
        vm.stopPrank();
        _;
    }

    function test_MintTokensAndUpdatePositionWhen_SharesBorrowOpeningFeeIsZero()
        external
        givenSharesIsProvided
        whenSharesIsGreaterThanZero
        whenSharesUserHasSufficientCollateral
    {
        // Set up with zero opening fee
        vm.prank(owner);
        market.setBorrowOpeningFee(0);

        uint256 shareAmount = 1 ether; // Minimal amount to avoid LTV issues
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();
        (, uint128 borrowSharesBefore,) = market.position(alice);

        vm.startPrank(alice);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) = market.borrow(0, shareAmount, alice, alice, "");
        vm.stopPrank();

        // it should mint tokens and update position
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        assertGt(aliceBalanceAfter, aliceBalanceBefore);
        assertEq(openingFeeAssets, 0);

        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);

        (, uint128 borrowSharesAfter,) = market.position(alice);
        assertGt(borrowSharesAfter, borrowSharesBefore);
    }

    function test_MintTokensAndUpdatePositionAndApplyFeeWhen_SharesBorrowOpeningFeeIsGreaterThanZero()
        external
        givenSharesIsProvided
        whenSharesIsGreaterThanZero
        whenSharesUserHasSufficientCollateral
    {
        uint256 shareAmount = 1 ether; // Minimal amount to avoid LTV issues
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        (uint128 totalBorrowedAssetsBefore,) = market.totalBorrowed();
        (, uint128 borrowSharesBefore,) = market.position(alice);

        vm.startPrank(alice);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) = market.borrow(0, shareAmount, alice, alice, "");
        vm.stopPrank();

        // it should mint tokens, update position and apply fee
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        assertGt(aliceBalanceAfter, aliceBalanceBefore);
        assertGt(openingFeeAssets, 0);

        (uint128 totalBorrowedAssetsAfter,) = market.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);

        (, uint128 borrowSharesAfter,) = market.position(alice);
        assertGt(borrowSharesAfter, borrowSharesBefore);
    }
}
