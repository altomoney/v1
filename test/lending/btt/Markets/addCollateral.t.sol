// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {IMarketErrors, IMarketEvents, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract AltoMarketAddCollateral is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.addCollateral(100 ether, USER);
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.prank(PAUSER);
        market.pause(FROZEN_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.addCollateral(100 ether, USER);
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_AssetsIsZero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addCollateral(0, USER);
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.addCollateral(1 ether, address(0));
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_UserHasInsufficientBalance() external givenValidInputs {
        uint256 excessiveAmount = collateralToken.balanceOf(USER) + 1;

        vm.startPrank(USER);
        collateralToken.approve(address(market), excessiveAmount);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, USER, collateralToken.balanceOf(USER), excessiveAmount
            )
        );
        market.addCollateral(excessiveAmount, USER);
        vm.stopPrank();
    }

    function test_WhenUserHasSufficientBalance() external givenValidInputs {
        uint256 collateralAmount = 100 ether;
        deal(address(collateralToken), USER, collateralAmount);
        uint256 userBalanceBefore = collateralToken.balanceOf(USER);
        uint256 marketBalanceBefore = collateralToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);

        vm.startPrank(USER);
        collateralToken.approve(address(market), collateralAmount);
        // it should emit AddCollateral event
        vm.expectEmit();
        emit IMarketEvents.AddCollateral(USER, USER, collateralAmount);
        uint256 returnedAmount = market.addCollateral(collateralAmount, USER);

        vm.stopPrank();

        uint256 userBalanceAfter = collateralToken.balanceOf(USER);
        uint256 marketBalanceAfter = collateralToken.balanceOf(address(market));
        Position memory positionAfter = market.position(USER);

        // it should add collateral to position
        assertEq(positionAfter.collateralAssets, positionBefore.collateralAssets + collateralAmount);

        // it should transfer collateral tokens from sender
        assertEq(userBalanceAfter, userBalanceBefore - collateralAmount);
        assertEq(marketBalanceAfter, marketBalanceBefore + collateralAmount);

        // it should return the amount of assets added
        assertEq(returnedAmount, collateralAmount);
    }
}
