// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {IMintCurveConvexPositionErrors, IMintCurveConvexPositionEvents} from
    "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {stdError} from "forge-std/StdError.sol";

contract MintCurveConvexPosition_WithdrawFromLpAndRepay_Test is MintCurveConvexPositionCommon {
    uint256 internal constant CRV_REWARD = 5e18;
    uint256 internal constant CVX_REWARD = 3e18;

    function setUp() public override {
        super.setUp();
        _openPosition(DEFAULT_COLLATERAL, DEFAULT_BORROW);
    }

    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, false);
    }

    function test_RevertWhen_LpToWithdrawAndSharesToRepayAreZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.withdrawFromLpAndRepay(0, 0, 0, false);
    }

    function test_RevertWhen_LpToWithdrawIsZeroAndMinBorrowTokenOutIsGreaterThanZero() public {
        uint256 shares = _borrowShares();
        _fundOwnerDusd(DEFAULT_BORROW * 2);

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.withdrawFromLpAndRepay(0, 1, shares, false);
    }

    function test_RevertWhen_LpToWithdrawIsZeroAndClaimRewardsIsTrue() public {
        uint256 shares = _borrowShares();
        _fundOwnerDusd(DEFAULT_BORROW * 2);

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.withdrawFromLpAndRepay(0, 0, shares, true);
    }

    function test_RevertWhen_StakedLpIsLessThanLpToWithdraw() public {
        uint256 tooMuchLp = _stakedLpBalance() + 1;
        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        position.withdrawFromLpAndRepay(tooMuchLp, 0, 0, false);
    }

    function test_RevertWhen_ConvexWithdrawReturnsFalse() public {
        vm.mockCall(
            address(convexRewardPool),
            abi.encodeWithSignature("withdrawAndUnwrap(uint256,bool)"),
            abi.encode(false)
        );

        vm.prank(OWNER);
        vm.expectRevert(
            IMintCurveConvexPositionErrors.MintCurveConvexPositionWithdrawalFromConvexRewardPoolFailed.selector
        );
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, 0, 0, false);
    }

    function test_RevertWhen_BorrowTokenReceivedIsLessThanMinBorrowTokenOut() public {
        // Default one-coin output is 1:1 with the burnt LP, so requiring more reverts.
        vm.prank(OWNER);
        vm.expectPartialRevert(MockCurvePool.MockCurvePoolMinReceivedNotMet.selector);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW + 1, 0, false);
    }

    function test_WithdrawFromLpAndRepay_WhenClaimRewardsIsTrue() public {
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardsClaimed(CRV_REWARD, CVX_REWARD);
        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, 0);
        vm.prank(OWNER);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, true);

        assertTrue(convexRewardPool.lastWithdrawClaimRewards(), "unwrapped claiming rewards");
        assertEq(convexRewardPool.lastWithdrawAmount(), DEFAULT_BORROW, "full lp unwound");
        assertEq(curvePool.removeLiquidityCallCount(), 1, "curve removed one-sided");
        assertEq(curvePool.lastRemoveIndex(), 0, "dusd removed at index 0");
        assertEq(crv.balanceOf(OWNER), CRV_REWARD, "crv to owner");
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD, "cvx to owner");
        assertEq(borrowToken.balanceOf(OWNER), DEFAULT_BORROW, "dusd swept to owner");
        assertEq(_stakedLpBalance(), 0, "lp fully unstaked");
    }

    function test_WithdrawFromLpAndRepay_WhenClaimRewardsIsFalse() public {
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, 0);
        vm.prank(OWNER);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, false);

        assertFalse(convexRewardPool.lastWithdrawClaimRewards(), "unwrapped without claiming");
        assertEq(curvePool.removeLiquidityCallCount(), 1, "curve removed one-sided");
        assertEq(crv.balanceOf(OWNER), 0, "no crv moved");
        assertEq(cvx.balanceOf(OWNER), 0, "no cvx moved");
        assertEq(crv.balanceOf(address(convexRewardPool)), CRV_REWARD, "rewards stay in pool");
        assertEq(borrowToken.balanceOf(OWNER), DEFAULT_BORROW, "dusd swept to owner");
    }

    function test_RevertWhen_SharesToRepayExceedsBorrowShares() public {
        borrowToken.mint(address(position), DEFAULT_BORROW * 4);
        uint256 shares = _borrowShares() + 1e18;

        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        position.withdrawFromLpAndRepay(0, 0, shares, false);
    }

    function test_RevertWhen_RepayCannotCoverBorrowToken() public {
        // No LP unwind and no owner funds means the required DUSD cannot be sourced.
        uint256 shares = _borrowShares();
        vm.prank(OWNER);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        position.withdrawFromLpAndRepay(0, 0, shares, false);
    }

    function test_WithdrawFromLpAndRepay_RepaysAndPullsShortfallFromOwner() public {
        uint256 shares = _borrowShares();
        uint256 partialLp = DEFAULT_BORROW / 5; // one-sided removal yields less DUSD than the debt
        _fundOwnerDusd(DEFAULT_BORROW * 2);
        uint256 ownerDusdBefore = borrowToken.balanceOf(OWNER);

        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(OWNER, shares, 0);
        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, partialLp, partialLp, shares);
        vm.prank(OWNER);
        position.withdrawFromLpAndRepay(partialLp, partialLp, shares, false);

        assertEq(_borrowShares(), 0, "debt cleared");
        assertLt(borrowToken.balanceOf(OWNER), ownerDusdBefore, "shortfall pulled from owner");
        assertEq(_stakedLpBalance(), DEFAULT_BORROW - partialLp, "lp partially unstaked");
    }

    function test_WithdrawFromLpAndRepay_RepaysFromLpProceedsAndSweepsSurplus() public {
        // Unwinding the full LP yields ~DEFAULT_BORROW of DUSD; repaying half the debt is funded
        // entirely from those proceeds, and the surplus is swept to the owner without any top-up.
        uint256 shares = _borrowShares();
        uint256 repayShares = shares / 2;
        assertGt(repayShares, 0);

        // Owner holds no DUSD and grants no allowance: if the position tried to pull a shortfall it would revert.
        uint256 ownerDusdBefore = borrowToken.balanceOf(OWNER);
        assertEq(ownerDusdBefore, 0, "owner starts with no dusd");

        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(OWNER, repayShares, 0);
        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, repayShares);
        vm.prank(OWNER);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, repayShares, false);

        assertEq(_borrowShares(), shares - repayShares, "only repayShares repaid");
        assertEq(_stakedLpBalance(), 0, "lp fully unstaked");
        assertEq(borrowToken.balanceOf(address(position)), 0, "no residual dusd in position");
        assertGt(borrowToken.balanceOf(OWNER), ownerDusdBefore, "surplus proceeds swept to owner");
    }

    function test_WithdrawFromLpAndRepay_UnwindsRepaysAndClaimsRewardsInOneCall() public {
        _fundRewards(CRV_REWARD, CVX_REWARD);
        uint256 shares = _borrowShares();
        uint256 repayShares = shares / 2;
        assertGt(repayShares, 0);

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardsClaimed(CRV_REWARD, CVX_REWARD);
        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(OWNER, repayShares, 0);
        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, repayShares);
        vm.prank(OWNER);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, repayShares, true);

        assertEq(_stakedLpBalance(), 0, "lp fully unstaked");
        assertEq(_borrowShares(), shares - repayShares, "only repayShares repaid");
        assertTrue(convexRewardPool.lastWithdrawClaimRewards(), "unwrapped claiming rewards");
        assertEq(crv.balanceOf(OWNER), CRV_REWARD, "crv to owner");
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD, "cvx to owner");
        // Full unwind yields ~DEFAULT_BORROW; repaying half the debt leaves a surplus swept to the owner.
        assertGt(borrowToken.balanceOf(OWNER), 0, "surplus dusd swept to owner");
        assertEq(borrowToken.balanceOf(address(position)), 0, "no residual dusd");
    }

    function test_WithdrawFromLpAndRepay_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, 0);
        vm.prank(AUTHORIZED_SPENDER);
        position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, false);

        assertFalse(convexRewardPool.lastWithdrawClaimRewards(), "unwrapped without claiming");
        assertEq(convexRewardPool.lastWithdrawAmount(), DEFAULT_BORROW, "full lp unwound");
        assertEq(curvePool.removeLiquidityCallCount(), 1, "curve removed one-sided");
        assertEq(curvePool.lastRemoveIndex(), 0, "dusd removed at index 0");
        assertEq(crv.balanceOf(OWNER), 0, "no crv moved");
        assertEq(cvx.balanceOf(OWNER), 0, "no cvx moved");
        assertEq(crv.balanceOf(address(convexRewardPool)), CRV_REWARD, "rewards stay in pool");
        assertEq(_stakedLpBalance(), 0, "lp fully unstaked");
        assertEq(borrowToken.balanceOf(OWNER), DEFAULT_BORROW, "dusd swept to owner");
    }
}
