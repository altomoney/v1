// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionErrors,
    IMintCurveConvexPositionEvents
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {MockConvexExtraRewardPool} from "../mocks/MockConvexExtraRewardPool.sol";
import {MockConvexStashTokenWrapper} from "../mocks/MockConvexStashTokenWrapper.sol";
import {MockTokenizedVaultReward} from "../mocks/MockTokenizedVaultReward.sol";

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

        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(crv), CRV_REWARD);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(cvx), CVX_REWARD);
        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(convexRewardPool.claimRewardsCallCount(), 1, "reward pool claimed");
        assertEq(tokens.length, 2, "all configured rewards returned");
        assertEq(amounts.length, 2, "parallel amounts returned");
        assertEq(tokens[0], address(crv));
        assertEq(tokens[1], address(cvx));
        assertEq(amounts[0], CRV_REWARD);
        assertEq(amounts[1], CVX_REWARD);
        assertEq(crv.balanceOf(OWNER), CRV_REWARD, "full crv to owner");
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD, "full cvx to owner");
        assertEq(crv.balanceOf(address(position)), 0, "no crv left in position");
        assertEq(cvx.balanceOf(address(position)), 0, "no cvx left in position");
    }

    function test_ClaimRewards_WhenPositionHasNoRewards() public {
        vm.recordLogs();
        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(convexRewardPool.claimRewardsCallCount(), 1, "reward pool claimed");
        assertEq(tokens.length, 2);
        assertEq(amounts.length, 2);
        assertEq(tokens[0], address(crv));
        assertEq(tokens[1], address(cvx));
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(vm.getRecordedLogs().length, 0, "zero balances emit no reward events");
        assertEq(crv.balanceOf(OWNER), 0);
        assertEq(cvx.balanceOf(OWNER), 0);
    }

    function test_ClaimRewards_DiscoversNormalCvxWrapperDirectTokenAndDeduplicatesCvx() public {
        ERC20MockMintable wfrax = new ERC20MockMintable("Wrapped FRAX", "WFRAX");
        ERC20MockMintable directReward = new ERC20MockMintable("Direct reward", "DIRECT");
        MockConvexStashTokenWrapper wrapper = new MockConvexStashTokenWrapper(address(wfrax));
        MockConvexExtraRewardPool extraCvx = new MockConvexExtraRewardPool(address(cvx), address(cvx));
        MockConvexExtraRewardPool extraWfrax = new MockConvexExtraRewardPool(address(wrapper), address(wfrax));
        MockConvexExtraRewardPool extraDirect =
            new MockConvexExtraRewardPool(address(directReward), address(directReward));
        wrapper.setConvexContext(address(extraWfrax), address(convexBooster));

        // Add the streams after the position exists to prove discovery happens at claim time.
        convexRewardPool.addExtraReward(address(extraCvx));
        convexRewardPool.addExtraReward(address(extraWfrax));
        convexRewardPool.addExtraReward(address(extraDirect));

        _fundRewards(CRV_REWARD, CVX_REWARD);
        cvx.mint(address(extraCvx), 2e18);
        wfrax.mint(address(extraWfrax), 7e18);
        directReward.mint(address(extraDirect), 11e18);

        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(crv), CRV_REWARD);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(cvx), CVX_REWARD + 2e18);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(wfrax), 7e18);
        vm.expectEmit(true, true, false, true, address(position));
        emit IMintCurveConvexPositionEvents.RewardClaimed(OWNER, address(directReward), 11e18);

        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(tokens.length, 4, "cvx is returned only once");
        assertEq(amounts.length, 4);
        assertEq(tokens[0], address(crv));
        assertEq(tokens[1], address(cvx));
        assertEq(tokens[2], address(wfrax), "wrapper resolved to WFRAX");
        assertEq(tokens[3], address(directReward), "direct reward token retained");
        assertEq(amounts[0], CRV_REWARD);
        assertEq(amounts[1], CVX_REWARD + 2e18, "normal and extra CVX combined");
        assertEq(amounts[2], 7e18);
        assertEq(amounts[3], 11e18);
        assertEq(wfrax.balanceOf(OWNER), 7e18, "WFRAX transferred to owner");
        assertEq(directReward.balanceOf(OWNER), 11e18, "direct reward transferred to owner");
    }

    function test_ClaimRewards_DoesNotTreatArbitraryTokenGetterAsStashWrapper() public {
        ERC20MockMintable underlying = new ERC20MockMintable("Underlying", "UNDERLYING");
        MockTokenizedVaultReward vaultReward = new MockTokenizedVaultReward(address(underlying));
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(vaultReward), address(vaultReward));
        convexRewardPool.addExtraReward(address(extra));
        vaultReward.mint(address(extra), 8e18);

        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(tokens.length, 3);
        assertEq(tokens[2], address(vaultReward), "direct reward is not mistaken for its underlying");
        assertEq(amounts[2], 8e18);
        assertEq(vaultReward.balanceOf(OWNER), 8e18, "actual reward transferred");
        assertEq(underlying.balanceOf(OWNER), 0, "unrelated underlying not returned");
    }

    function test_ClaimRewards_SkipsExtraRewardsWhenLengthQueryReverts() public {
        _fundRewards(CRV_REWARD, CVX_REWARD);
        vm.mockCallRevert(
            address(convexRewardPool), abi.encodeWithSignature("extraRewardsLength()"), "length query failed"
        );

        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(tokens.length, 2);
        assertEq(amounts.length, 2);
        assertEq(tokens[0], address(crv));
        assertEq(tokens[1], address(cvx));
        assertEq(amounts[0], CRV_REWARD);
        assertEq(amounts[1], CVX_REWARD);
    }

    function test_ClaimRewards_SkipsMalformedExtraRewardPoolAddress() public {
        ERC20MockMintable extraToken = new ERC20MockMintable("Extra", "EXTRA");
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        convexRewardPool.addExtraReward(address(extra));
        extraToken.mint(address(extra), 6e18);
        vm.mockCall(
            address(convexRewardPool),
            abi.encodeWithSignature("extraRewards(uint256)", 0),
            abi.encode(makeAddr("MalformedExtraRewardPool"))
        );

        vm.prank(OWNER);
        (address[] memory tokens,) = position.claimRewards();

        assertEq(tokens.length, 2, "malformed pool skipped");
        assertEq(extraToken.balanceOf(address(position)), 6e18, "undiscovered reward remains recoverable");
    }

    function test_ClaimRewards_SkipsExtraPoolWhoseRewardTokenQueryReverts() public {
        ERC20MockMintable extraToken = new ERC20MockMintable("Extra", "EXTRA");
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        convexRewardPool.addExtraReward(address(extra));
        extra.setRewardTokenReverts(true);
        extraToken.mint(address(extra), 12e18);

        vm.prank(OWNER);
        (address[] memory tokens,) = position.claimRewards();

        assertEq(tokens.length, 2, "reverting metadata entry skipped");
        assertEq(extraToken.balanceOf(address(position)), 12e18, "undiscovered reward remains recoverable");
    }

    function test_ClaimRewards_DeduplicatesRepeatedExtraRewardTokens() public {
        ERC20MockMintable extraToken = new ERC20MockMintable("Extra", "EXTRA");
        MockConvexExtraRewardPool first = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        MockConvexExtraRewardPool second = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        convexRewardPool.addExtraReward(address(first));
        convexRewardPool.addExtraReward(address(second));
        extraToken.mint(address(first), 4e18);
        extraToken.mint(address(second), 6e18);

        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(tokens.length, 3);
        assertEq(tokens[2], address(extraToken));
        assertEq(amounts[2], 10e18);
        assertEq(extraToken.balanceOf(OWNER), 10e18);
    }

    function test_ClaimRewards_ReturnsZeroBalanceExtraRewardToken() public {
        ERC20MockMintable extraToken = new ERC20MockMintable("Extra", "EXTRA");
        MockConvexExtraRewardPool extra = new MockConvexExtraRewardPool(address(extraToken), address(extraToken));
        convexRewardPool.addExtraReward(address(extra));

        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(tokens.length, 3);
        assertEq(amounts.length, 3);
        assertEq(tokens[2], address(extraToken));
        assertEq(amounts[2], 0);
    }

    function test_ClaimRewards_SweepsRewardsAlreadyHeldByPosition() public {
        crv.mint(address(position), 13e18);
        cvx.mint(address(position), 17e18);
        _fundRewards(CRV_REWARD, CVX_REWARD);

        vm.prank(OWNER);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        assertEq(tokens[0], address(crv));
        assertEq(tokens[1], address(cvx));
        assertEq(amounts[0], CRV_REWARD + 13e18);
        assertEq(amounts[1], CVX_REWARD + 17e18);
        assertEq(crv.balanceOf(OWNER), CRV_REWARD + 13e18);
        assertEq(cvx.balanceOf(OWNER), CVX_REWARD + 17e18);
    }

    function test_ClaimRewards_UsesCurrentExtraRewardListAfterRemoval() public {
        ERC20MockMintable removedToken = new ERC20MockMintable("Removed", "REMOVED");
        MockConvexExtraRewardPool removed = new MockConvexExtraRewardPool(address(removedToken), address(removedToken));
        convexRewardPool.addExtraReward(address(removed));
        convexRewardPool.removeLastExtraReward();
        removedToken.mint(address(position), 1e18);

        vm.prank(OWNER);
        (address[] memory tokens,) = position.claimRewards();

        assertEq(tokens.length, 2, "removed stream is not returned");
        assertEq(removedToken.balanceOf(address(position)), 1e18, "unlisted token remains recoverable");
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
