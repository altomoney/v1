// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "./MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketErrors, IMarketEvents, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IRemoveCollateralCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";

contract RemoveCollateralCallback is IRemoveCollateralCallback {
    event RemovedCollateralCallback();

    function onRemoveCollateralCallback(uint256, address, bytes calldata) external {
        emit RemovedCollateralCallback();
    }
}

contract AltoMarketRemoveCollateral is MarketCommon {
    uint256 COLLATERAL_INPUT = 1 ether;

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.removeCollateral(COLLATERAL_INPUT, USER, USER, "");
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_AssetsIsZero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeCollateral(0, USER, USER, "");
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeCollateral(COLLATERAL_INPUT, address(0), USER, "");
    }

    modifier givenValidInputs() {
        vm.startPrank(USER);
        deal(address(collateralToken), USER, COLLATERAL_INPUT);
        collateralToken.approve(address(market), COLLATERAL_INPUT);
        market.addCollateral(COLLATERAL_INPUT, USER);
        vm.stopPrank();

        if (marketType == MarketType.BORROW) {
            deal(address(borrowToken), address(this), 100 ether);
            borrowToken.approve(address(market), 100 ether);
            market.addSupply(100 ether, 0, SUPPLIER);
        }
        _;
    }

    function test_RevertWhen_SenderIsNotAuthorized() external givenValidInputs {
        vm.prank(USER_2);
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.removeCollateral(COLLATERAL_INPUT, USER, USER, "");
    }

    function test_RevertWhen_DataIsProvidedButReceiverIsNotAuthorized() external givenValidInputs {
        vm.prank(USER);
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.removeCollateral(COLLATERAL_INPUT, USER, USER, "some_data");
    }

    function test_RevertWhen_PositionBecomesInsolventAfterRemoval() external givenValidInputs {
        vm.startPrank(USER);
        market.borrow(0.5 ether, 0, USER, USER, "");
        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientUserCollateral.selector);
        market.removeCollateral(COLLATERAL_INPUT - 0.5 ether, USER, USER, "");
        vm.stopPrank();
    }

    modifier whenAllConditionsAreMet() {
        vm.prank(USER);
        market.borrow(0.5 ether, 0, USER, USER, "");
        _;
    }

    function test_WhenAllConditionsAreMet() external givenValidInputs whenAllConditionsAreMet {
        uint256 userBalanceBefore = collateralToken.balanceOf(USER);
        uint256 marketBalanceBefore = collateralToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);

        uint256 removalAmount = COLLATERAL_INPUT - 0.7 ether;
        uint256 returnedAmount;
        {
            vm.startPrank(USER);
            // it should emit RemoveCollateral event
            vm.expectEmit(true, true, true, true);
            emit IMarketEvents.RemoveCollateral(USER, USER, USER, removalAmount);
            returnedAmount = market.removeCollateral(removalAmount, USER, USER, "");
            vm.stopPrank();
        }

        uint256 userBalanceAfter = collateralToken.balanceOf(USER);
        uint256 marketBalanceAfter = collateralToken.balanceOf(address(market));
        Position memory positionAfter = market.position(USER);

        // it should remove collateral from position
        assertEq(positionAfter.collateralAssets, positionBefore.collateralAssets - removalAmount);

        // it should transfer collateral tokens to receiver
        assertEq(userBalanceAfter, userBalanceBefore + removalAmount);
        assertEq(marketBalanceAfter, marketBalanceBefore - removalAmount);

        // it should return the amount of assets removed
        assertEq(returnedAmount, removalAmount);
    }

    function test_WhenCallbackDataIsProvidedAndReceiverIsAuthorized()
        external
        givenValidInputs
        whenAllConditionsAreMet
    {
        RemoveCollateralCallback callback = new RemoveCollateralCallback();

        vm.prank(OWNER);
        market.setAuthorizedCallback(address(callback), true);

        uint256 removalAmount = COLLATERAL_INPUT - 0.7 ether;
        {
            vm.startPrank(USER);

            // it should call onRemoveCollateralCallback
            vm.expectEmit(true, true, true, true);
            emit RemoveCollateralCallback.RemovedCollateralCallback();

            market.removeCollateral(removalAmount, USER, address(callback), "some_data");
            vm.stopPrank();
        }
    }
}
