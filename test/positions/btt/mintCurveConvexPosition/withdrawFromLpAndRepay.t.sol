// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionErrors,
    IMintCurveConvexPositionEvents
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {MockConvexExtraRewardPool} from "../mocks/MockConvexExtraRewardPool.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
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
            address(convexRewardPool), abi.encodeWithSignature("withdrawAndUnwrap(uint256,bool)"), abi.encode(false)
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
        ERC20MockMintable extraToken = new ERC20MockMintable("Extra", "EXTRA");
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        convexRewardPool.addExtraReward(address(extra));
        _fundRewards(CRV_REWARD, CVX_REWARD);
        extraToken.mint(address(extra), 9e18);

        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(crv), CRV_REWARD);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(cvx), CVX_REWARD);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(extraToken), 9e18);
        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, 0);
        vm.prank(OWNER);
        (uint256 borrowReceived, uint256 assetsRepaid, address[] memory tokens, uint256[] memory amounts) =
            position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, true);

        assertTrue(convexRewardPool.lastWithdrawClaimRewards(), "unwrapped claiming rewards");
        assertEq(borrowReceived, DEFAULT_BORROW);
        assertEq(assetsRepaid, 0);
        assertEq(tokens.length, 3, "dynamic reward-token array returned");
        assertEq(amounts.length, 3, "dynamic reward-amount array returned");
        assertEq(tokens[0], address(crv));
        assertEq(tokens[1], address(cvx));
        assertEq(tokens[2], address(extraToken));
        assertEq(amounts[0], CRV_REWARD);
        assertEq(amounts[1], CVX_REWARD);
        assertEq(amounts[2], 9e18);
        assertEq(convexRewardPool.lastWithdrawAmount(), DEFAULT_BORROW, "full lp unwound");
        assertEq(curvePool.removeLiquidityCallCount(), 1, "curve removed one-sided");
        assertEq(curvePool.lastRemoveIndex(), 0, "dusd removed at index 0");
        assertEq(crv.balanceOf(OWNER), CRV_REWARD, "crv to owner");
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD, "cvx to owner");
        assertEq(extraToken.balanceOf(OWNER), 9e18, "extra reward to owner");
        assertEq(borrowToken.balanceOf(OWNER), DEFAULT_BORROW, "dusd swept to owner");
        assertEq(_stakedLpBalance(), 0, "lp fully unstaked");
    }

    function test_WithdrawFromLpAndRepay_WhenClaimRewardsIsFalse() public {
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(OWNER, DEFAULT_BORROW, DEFAULT_BORROW, 0);
        vm.prank(OWNER);
        (,, address[] memory tokens, uint256[] memory amounts) =
            position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, false);

        assertFalse(convexRewardPool.lastWithdrawClaimRewards(), "unwrapped without claiming");
        assertEq(tokens.length, 0, "no reward tokens returned when claiming is disabled");
        assertEq(amounts.length, 0, "no reward amounts returned when claiming is disabled");
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

        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(OWNER, repayShares, 0);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(crv), CRV_REWARD);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(cvx), CVX_REWARD);
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

    function test_WithdrawFromLpAndRepay_RepaysBeforeSweepingBorrowTokenReward() public {
        uint256 borrowReward = 25e18;
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(borrowToken), address(borrowToken));
        convexRewardPool.addExtraReward(address(extra));
        borrowToken.mint(address(extra), borrowReward);
        uint256 shares = _borrowShares();
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);

        vm.prank(AUTHORIZED_SPENDER);
        (uint256 borrowReceived, uint256 assetsRepaid, address[] memory tokens, uint256[] memory amounts) =
            position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, shares, true);

        assertEq(borrowReceived, DEFAULT_BORROW);
        assertEq(assetsRepaid, DEFAULT_BORROW);
        assertEq(_borrowShares(), 0, "LP proceeds repaid the debt");
        assertEq(borrowToken.balanceOf(AUTHORIZED_SPENDER), 0, "authorized caller did not fund repayment");
        assertEq(tokens.length, 3);
        assertEq(tokens[2], address(borrowToken));
        assertEq(amounts[2], borrowReward, "only the post-repayment reward was swept");
        assertEq(borrowToken.balanceOf(OWNER), borrowReward, "borrow-token reward transferred to owner");
    }

    function test_WithdrawFromLpAndRepay_SkipsMalformedExtraRewardMetadata() public {
        ERC20MockMintable extraToken = new ERC20MockMintable("Extra", "EXTRA");
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        convexRewardPool.addExtraReward(address(extra));
        extra.setRewardTokenReverts(true);
        extraToken.mint(address(extra), 4e18);

        vm.prank(OWNER);
        (,, address[] memory tokens, uint256[] memory amounts) =
            position.withdrawFromLpAndRepay(DEFAULT_BORROW, DEFAULT_BORROW, 0, true);

        assertEq(tokens.length, 2, "malformed entry skipped during unwind claim");
        assertEq(amounts.length, 2);
        assertEq(extraToken.balanceOf(address(position)), 4e18, "skipped reward remains recoverable");
        assertEq(borrowToken.balanceOf(OWNER), DEFAULT_BORROW, "unwind still succeeds");
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
