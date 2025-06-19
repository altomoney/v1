// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";

contract AddCollateralTest is AltoMintMarketTest {
    function setUp() public override {
        super.setUp();

        // Set owner as pauser for both pause types
        vm.startPrank(owner);
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPauser(owner, FROZEN_MARKET, true);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.addCollateral(100 ether, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.startPrank(owner);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.addCollateral(100 ether, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_AssetsIsZero() external {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.addCollateral(0, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.addCollateral(100 ether, address(0));
        vm.stopPrank();
    }

    modifier givenAssetsIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_UserHasInsufficientBalance() external givenAssetsIsGreaterThanZero {
        uint256 excessiveAmount = collateralToken.balanceOf(alice) + 1;

        vm.startPrank(alice);
        vm.expectRevert();
        market.addCollateral(excessiveAmount, alice);
        vm.stopPrank();
    }

    function test_AddCollateralToPositionWhen_UserHasSufficientBalance() external givenAssetsIsGreaterThanZero {
        uint256 collateralAmount = 100 ether;
        uint256 aliceBalanceBefore = collateralToken.balanceOf(alice);
        uint256 marketBalanceBefore = collateralToken.balanceOf(address(market));
        (,, uint128 collateralAssetsBefore) = market.position(alice);

        vm.startPrank(alice);
        market.addCollateral(collateralAmount, alice);
        vm.stopPrank();

        // it should add collateral to position
        uint256 aliceBalanceAfter = collateralToken.balanceOf(alice);
        uint256 marketBalanceAfter = collateralToken.balanceOf(address(market));
        assertEq(aliceBalanceAfter, aliceBalanceBefore - collateralAmount);
        assertEq(marketBalanceAfter, marketBalanceBefore + collateralAmount);

        (,, uint128 collateralAssetsAfter) = market.position(alice);
        assertEq(collateralAssetsAfter, collateralAssetsBefore + collateralAmount);
    }
}
