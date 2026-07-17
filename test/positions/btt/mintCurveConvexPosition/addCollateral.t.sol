// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {IMintCurveConvexPositionErrors, IMintCurveConvexPositionEvents} from
    "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MintCurveConvexPosition_AddCollateral_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.addCollateral(DEFAULT_COLLATERAL);
    }

    function test_RevertWhen_AmountIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.addCollateral(0);
    }

    function test_RevertWhen_OwnerHasNotApprovedCollateral() public {
        collateralToken.mint(OWNER, DEFAULT_COLLATERAL);
        // No approval granted to the position.
        vm.prank(OWNER);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        position.addCollateral(DEFAULT_COLLATERAL);
    }

    function test_RevertWhen_OwnerHasInsufficientCollateralBalance() public {
        // Approve but never fund the owner.
        vm.prank(OWNER);
        collateralToken.approve(address(position), DEFAULT_COLLATERAL);

        vm.prank(OWNER);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        position.addCollateral(DEFAULT_COLLATERAL);
    }

    function test_AddCollateral_WhenApprovedAndFunded() public {
        _fundOwnerCollateral(DEFAULT_COLLATERAL);

        uint256 marketCollateralBefore = _marketPosition().collateralAssets;

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.CollateralAdded(DEFAULT_COLLATERAL);
        vm.prank(OWNER);
        position.addCollateral(DEFAULT_COLLATERAL);

        assertEq(_marketPosition().collateralAssets, marketCollateralBefore + DEFAULT_COLLATERAL);
        assertEq(collateralToken.balanceOf(OWNER), 0, "owner collateral pulled");
        assertEq(IERC20(collateralToken).allowance(address(position), address(mintMarket)), 0, "allowance reset");
    }

    function test_AddCollateral_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        // Collateral is pulled from the caller (the authorized spender).
        _fundCollateral(AUTHORIZED_SPENDER, DEFAULT_COLLATERAL);

        vm.prank(AUTHORIZED_SPENDER);
        position.addCollateral(DEFAULT_COLLATERAL);

        assertEq(_marketPosition().collateralAssets, DEFAULT_COLLATERAL);
        assertEq(collateralToken.balanceOf(AUTHORIZED_SPENDER), 0, "spender collateral pulled");
    }
}
