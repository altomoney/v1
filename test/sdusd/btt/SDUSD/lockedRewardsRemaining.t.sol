// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_LockedRewardsRemaining_Test is SDUSDCommon {
    function test_ReturnsZeroBeforeAnyRewardPeriod() public view {
        assertEq(vault.lockedRewardsRemaining(), 0);
    }

    function test_ReturnsFullRewardAtPeriodStart() public {
        _notifyRewards(REWARD_AMOUNT);
        assertEq(vault.lockedRewardsRemaining(), REWARD_AMOUNT);
    }

    function test_CalculatesLinearRemainingRewardAndRoundsUp() public {
        uint256 amount = REWARD_AMOUNT + 1;
        _notifyRewards(amount);
        uint256 elapsed = REWARD_DURATION / 3;
        vm.warp(vault.periodStart() + elapsed);
        uint256 roundedDown = amount * (REWARD_DURATION - elapsed) / REWARD_DURATION;

        assertEq(vault.lockedRewardsRemaining(), roundedDown + 1);
    }

    function test_ReturnsFinalLockedFractionImmediatelyBeforeFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.rewardPeriodFinish() - 1);
        assertEq(vault.lockedRewardsRemaining(), REWARD_AMOUNT / REWARD_DURATION + 1);
    }

    function test_DoesNotAddExtraWeiWhenLinearFractionDividesExactly() public {
        uint256 exactRewardPerSecond = 1 ether;
        uint256 amount = REWARD_DURATION * exactRewardPerSecond;
        _notifyRewards(amount);
        vm.warp(vault.rewardPeriodFinish() - 1);

        assertEq(vault.lockedRewardsRemaining(), exactRewardPerSecond);
    }

    function test_ReturnsZeroAtRewardPeriodFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        assertEq(vault.lockedRewardsRemaining(), 0);
    }

    function test_ReturnsZeroAfterRewardPeriodFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.rewardPeriodFinish() + 1);
        assertEq(vault.lockedRewardsRemaining(), 0);
    }
}
