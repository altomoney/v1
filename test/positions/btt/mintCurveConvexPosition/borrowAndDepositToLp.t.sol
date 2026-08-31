// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionErrors,
    IMintCurveConvexPositionEvents
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {MockConvexBooster} from "../mocks/MockConvexBooster.sol";
import {MockConvexRewardPool} from "../mocks/MockConvexRewardPool.sol";

contract MintCurveConvexPosition_BorrowAndDepositToLp_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        _seedCollateral(DEFAULT_COLLATERAL);

        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);
    }

    function test_RevertWhen_BorrowAssetsIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.borrowAndDepositToLp(0, 0);
    }

    function test_RevertWhen_BorrowExceedsMaxLtv() public {
        // No collateral posted, so any borrow leaves the position insolvent.
        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);
    }

    function test_RevertWhen_MintedLpIsLessThanMinLpOut() public {
        _seedCollateral(DEFAULT_COLLATERAL);
        curvePool.setLpMintOverride(DEFAULT_BORROW - 1, true);

        vm.prank(OWNER);
        vm.expectPartialRevert(MockCurvePool.MockCurvePoolMinLpNotMet.selector);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);
    }

    function test_RevertWhen_ConvexStakingReturnsFalse() public {
        _seedCollateral(DEFAULT_COLLATERAL);
        vm.mockCall(address(convexBooster), abi.encodeWithSignature("deposit(uint256,uint256,bool)"), abi.encode(false));

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionStakingFailed.selector);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);
    }

    function test_BorrowAndDepositToLp_WhenDusdIsCoin0() public {
        _seedCollateral(DEFAULT_COLLATERAL);

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Deposited(DEFAULT_BORROW, DEFAULT_BORROW);
        vm.prank(OWNER);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);

        // DUSD supplied one-sided at index 0.
        assertEq(curvePool.lastAmount0(), DEFAULT_BORROW, "dusd at index 0");
        assertEq(curvePool.lastAmount1(), 0, "no pair token");

        // Borrowed DUSD to the position and staked the LP.
        assertGt(_borrowShares(), 0, "borrow shares opened");
        assertEq(_stakedLpBalance(), DEFAULT_BORROW, "lp staked in convex");

        // Allowances reset after use.
        assertEq(IERC20(borrowToken).allowance(address(position), address(curvePool)), 0, "curve allowance reset");
        assertEq(
            IERC20(address(curvePool)).allowance(address(position), address(convexBooster)), 0, "convex allowance reset"
        );
        // DUSD fully deployed into Curve, nothing left in the position.
        assertEq(borrowToken.balanceOf(address(position)), 0, "no residual dusd");
    }

    function test_BorrowAndDepositToLp_WhenDusdIsCoin1() public {
        // Deploy a position from a factory configured with a pool where DUSD is coin1.
        MockCurvePool pool1 = new MockCurvePool(address(pairToken), address(borrowToken));
        MockConvexRewardPool rp1 = new MockConvexRewardPool(address(pool1), address(crv), address(cvx), 1);
        MockConvexBooster b1 = new MockConvexBooster(address(rp1), address(pool1));

        position = _createPositionWithConfig(_config(address(pool1), address(b1), address(rp1)));

        _seedCollateral(DEFAULT_COLLATERAL);
        vm.prank(OWNER);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);

        assertEq(pool1.lastAmount1(), DEFAULT_BORROW, "dusd at index 1");
        assertEq(pool1.lastAmount0(), 0, "no pair token");
        assertEq(rp1.balanceOf(address(position)), DEFAULT_BORROW, "lp staked in convex");
    }

    function test_BorrowAndDepositToLp_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _seedCollateral(DEFAULT_COLLATERAL);

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Deposited(DEFAULT_BORROW, DEFAULT_BORROW);
        vm.prank(AUTHORIZED_SPENDER);
        position.borrowAndDepositToLp(DEFAULT_BORROW, DEFAULT_BORROW);

        // DUSD supplied one-sided at index 0.
        assertEq(curvePool.lastAmount0(), DEFAULT_BORROW, "dusd at index 0");
        assertEq(curvePool.lastAmount1(), 0, "no pair token");

        // Borrowed DUSD to the position and staked the LP.
        assertGt(_borrowShares(), 0, "borrow shares opened");
        assertEq(_stakedLpBalance(), DEFAULT_BORROW, "lp staked in convex");

        // Allowances reset after use.
        assertEq(IERC20(borrowToken).allowance(address(position), address(curvePool)), 0, "curve allowance reset");
        assertEq(
            IERC20(address(curvePool)).allowance(address(position), address(convexBooster)), 0, "convex allowance reset"
        );
        // DUSD fully deployed into Curve, nothing left in the position.
        assertEq(borrowToken.balanceOf(address(position)), 0, "no residual dusd");
    }
}
