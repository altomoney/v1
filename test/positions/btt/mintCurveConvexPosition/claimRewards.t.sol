// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionEvents,
    IMintCurveConvexPositionErrors
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";

contract MintCurveConvexPosition_ClaimRewards_Test is MintCurveConvexPositionCommon {
    uint256 internal constant CRV_REWARD = 100e18;
    uint256 internal constant CVX_REWARD = 50e18;

    function setUp() public override {
        super.setUp();
        _fundRewards(CRV_REWARD, CVX_REWARD);
    }

    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.claimRewards();
    }

    function test_ClaimRewards_WhenCallerIsAuthorizedSpenderAndNotOwner() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);

        vm.prank(AUTHORIZED_SPENDER);
        position.claimRewards();

        assertEq(crv.balanceOf(OWNER), CRV_REWARD);
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD);
        assertEq(crv.balanceOf(address(position)), 0);
        assertEq(cvx.balanceOf(address(position)), 0);
    }

    function test_ClaimRewards_ClaimsFromConfiguredConvexRewardPool() public {
        vm.prank(OWNER);
        position.claimRewards();

        assertEq(convexRewardPool.claimRewardsCallCount(), 1);
    }

    function test_ClaimRewards_TransfersFullRewardBalancesToOwner() public {
        vm.prank(OWNER);
        position.claimRewards();

        assertEq(crv.balanceOf(OWNER), CRV_REWARD);
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD);
        assertEq(crv.balanceOf(address(position)), 0);
        assertEq(cvx.balanceOf(address(position)), 0);
    }

    function test_ClaimRewards_EmitsClaimRewardsWithTransferredAmounts() public {
        vm.expectEmit(true, false, false, true);
        emit IMintCurveConvexPositionEvents.ClaimRewards(OWNER, CRV_REWARD, CVX_REWARD);

        vm.prank(OWNER);
        position.claimRewards();
    }
}
