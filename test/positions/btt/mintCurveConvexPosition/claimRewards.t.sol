// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionErrors,
    IMintCurveConvexPositionEvents
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";

contract MintCurveConvexPosition_ClaimRewards_Test is MintCurveConvexPositionCommon {
    uint256 internal constant CRV_REWARD = 5e18;
    uint256 internal constant CVX_REWARD = 3e18;

    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.claimRewards();
    }

    function test_RevertWhen_ConvexClaimReturnsFalse() public {
        vm.mockCall(address(convexRewardPool), abi.encodeWithSignature("getReward()"), abi.encode(false));

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionClaimingRewardsFailed.selector);
        position.claimRewards();
    }

    function test_ClaimRewards_WhenPositionHasRewards() public {
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardsClaimed(CRV_REWARD, CVX_REWARD);
        vm.prank(OWNER);
        position.claimRewards();

        assertEq(convexRewardPool.claimRewardsCallCount(), 1, "reward pool claimed");
        assertEq(crv.balanceOf(OWNER), CRV_REWARD, "full crv to owner");
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD, "full cvx to owner");
        assertEq(crv.balanceOf(address(position)), 0, "no crv left in position");
        assertEq(cvx.balanceOf(address(position)), 0, "no cvx left in position");
    }

    function test_ClaimRewards_WhenPositionHasNoRewards() public {
        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardsClaimed(0, 0);
        vm.prank(OWNER);
        position.claimRewards();

        assertEq(convexRewardPool.claimRewardsCallCount(), 1, "reward pool claimed");
        assertEq(crv.balanceOf(OWNER), 0);
        assertEq(cvx.balanceOf(OWNER), 0);
    }

    function test_ClaimRewards_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.prank(AUTHORIZED_SPENDER);
        position.claimRewards();

        assertEq(crv.balanceOf(OWNER), CRV_REWARD, "crv to owner");
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD, "cvx to owner");
    }
}
