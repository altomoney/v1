// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionErrors,
    IMintCurveConvexPositionEvents
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {stdError} from "forge-std/StdError.sol";

contract MintCurveConvexPosition_RemoveCollateral_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        _seedCollateral(DEFAULT_COLLATERAL);

        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.removeCollateral(DEFAULT_COLLATERAL);
    }

    function test_RevertWhen_AmountIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.removeCollateral(0);
    }

    function test_RevertWhen_AmountExceedsPostedCollateral() public {
        _seedCollateral(DEFAULT_COLLATERAL);

        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        position.removeCollateral(DEFAULT_COLLATERAL + 1);
    }

    function test_RevertWhen_WithdrawalLeavesPositionInsolvent() public {
        // Debt of DEFAULT_BORROW requires >= DEFAULT_BORROW / MAX_LTV collateral to stay solvent.
        _openPosition(DEFAULT_COLLATERAL, DEFAULT_BORROW);

        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientUserCollateral.selector);
        position.removeCollateral(DEFAULT_COLLATERAL); // leaves zero collateral against outstanding debt
    }

    function test_RemoveCollateral_WhenPositionStaysSolvent() public {
        _seedCollateral(DEFAULT_COLLATERAL);
        uint256 withdrawAmount = DEFAULT_COLLATERAL / 4;

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.CollateralRemoved(withdrawAmount);
        vm.prank(OWNER);
        position.removeCollateral(withdrawAmount);

        assertEq(_marketPosition().collateralAssets, DEFAULT_COLLATERAL - withdrawAmount);
        assertEq(collateralToken.balanceOf(OWNER), withdrawAmount, "collateral sent to owner");
    }

    function test_RemoveCollateral_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _seedCollateral(DEFAULT_COLLATERAL);

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.CollateralRemoved(DEFAULT_COLLATERAL);
        vm.prank(AUTHORIZED_SPENDER);
        position.removeCollateral(DEFAULT_COLLATERAL);

        assertEq(_marketPosition().collateralAssets, 0);
        assertEq(collateralToken.balanceOf(OWNER), DEFAULT_COLLATERAL, "collateral returned to owner");
    }
}
