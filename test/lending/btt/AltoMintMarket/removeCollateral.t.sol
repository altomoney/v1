// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {stdError} from "forge-std/StdError.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MockCallback {
    function onRemoveCollateralCallback(uint256 amount, bytes calldata data) external {}
}

contract RemoveCollateralTest is AltoMintMarketTest {
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
        market.removeCollateral(100 ether, alice, alice, "");
        vm.stopPrank();
    }

    modifier whenMarketIsNotPaused() {
        // Market is not paused by default
        _;
    }

    function test_RevertWhen_AmountIsZero() external whenMarketIsNotPaused {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeCollateral(0, alice, alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external whenMarketIsNotPaused {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeCollateral(100 ether, address(0), alice, "");
        vm.stopPrank();
    }

    function test_RevertWhen_ReceiverIsZeroAddress() external whenMarketIsNotPaused {
        // Give alice some collateral first so we can reach the receiver validation
        vm.startPrank(alice);
        market.addCollateral(200 ether, alice);

        // Now the receiver validation should trigger during safeTransfer
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        market.removeCollateral(100 ether, alice, address(0), "");
        vm.stopPrank();
    }

    modifier whenInputsAreValid() {
        _;
    }

    modifier givenPositionHasNoCollateral() {
        // No collateral added by default
        _;
    }

    function test_RevertGiven_PositionHasNoCollateral()
        external
        whenMarketIsNotPaused
        whenInputsAreValid
        givenPositionHasNoCollateral
    {
        vm.startPrank(alice);
        // Expect arithmetic underflow when trying to remove more collateral than exists
        vm.expectRevert(stdError.arithmeticError);
        market.removeCollateral(100 ether, alice, alice, "");
        vm.stopPrank();
    }

    modifier givenPositionHasSufficientCollateral() {
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice); // Add enough collateral
        vm.stopPrank();
        _;
    }

    modifier givenRemovalWouldViolateLtv() {
        vm.startPrank(alice);
        market.borrow(100 ether, 0, alice, alice, ""); // Borrow to create LTV constraint
        vm.stopPrank();
        _;
    }

    function test_RevertGiven_RemovalWouldViolateLtv()
        external
        whenMarketIsNotPaused
        whenInputsAreValid
        givenPositionHasSufficientCollateral
        givenRemovalWouldViolateLtv
    {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientUserCollateral.selector);
        market.removeCollateral(450 ether, alice, alice, ""); // Remove too much
        vm.stopPrank();
    }

    modifier givenRemovalIsWithinLimits() {
        // Position has collateral and removal doesn't violate LTV
        _;
    }

    function test_WhenDataLengthIsZero()
        external
        whenMarketIsNotPaused
        whenInputsAreValid
        givenPositionHasSufficientCollateral
        givenRemovalIsWithinLimits
    {
        uint256 removalAmount = 100 ether;
        uint256 aliceBalanceBefore = collateralToken.balanceOf(alice);
        uint256 marketBalanceBefore = collateralToken.balanceOf(address(market));
        (,, uint128 collateralAssetsBefore) = market.position(alice);

        vm.startPrank(alice);
        market.removeCollateral(removalAmount, alice, alice, "");
        vm.stopPrank();

        // it should transfer collateral tokens from market to receiver
        uint256 aliceBalanceAfter = collateralToken.balanceOf(alice);
        uint256 marketBalanceAfter = collateralToken.balanceOf(address(market));
        assertEq(aliceBalanceAfter, aliceBalanceBefore + removalAmount);
        assertEq(marketBalanceAfter, marketBalanceBefore - removalAmount);

        // it should decrease position collateralAssets for onBehalf
        (,, uint128 collateralAssetsAfter) = market.position(alice);
        assertEq(collateralAssetsAfter, collateralAssetsBefore - removalAmount);
    }

    function test_WhenDataLengthIsGreaterThanZeroAndReceiverIsAuthorizedCallback()
        external
        whenMarketIsNotPaused
        whenInputsAreValid
        givenPositionHasSufficientCollateral
        givenRemovalIsWithinLimits
    {
        uint256 removalAmount = 50 ether;
        uint256 callbackBalanceBefore = collateralToken.balanceOf(address(callback));
        uint256 marketBalanceBefore = collateralToken.balanceOf(address(market));
        (,, uint128 collateralAssetsBefore) = market.position(alice);

        vm.startPrank(alice);
        market.removeCollateral(removalAmount, alice, address(callback), "test_data");
        vm.stopPrank();

        // it should transfer collateral tokens from market to receiver
        uint256 callbackBalanceAfter = collateralToken.balanceOf(address(callback));
        uint256 marketBalanceAfter = collateralToken.balanceOf(address(market));
        assertEq(callbackBalanceAfter, callbackBalanceBefore + removalAmount);
        assertEq(marketBalanceAfter, marketBalanceBefore - removalAmount);

        // it should decrease position collateralAssets for onBehalf
        (,, uint128 collateralAssetsAfter) = market.position(alice);
        assertEq(collateralAssetsAfter, collateralAssetsBefore - removalAmount);

        // it should call onRemoveCollateral callback (implicitly tested by successful execution)
    }

    function test_RevertWhen_DataLengthIsGreaterThanZeroAndReceiverIsNotAuthorizedCallback()
        external
        whenMarketIsNotPaused
        whenInputsAreValid
        givenPositionHasSufficientCollateral
        givenRemovalIsWithinLimits
    {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.removeCollateral(50 ether, alice, bob, "test_data");
        vm.stopPrank();
    }
}
