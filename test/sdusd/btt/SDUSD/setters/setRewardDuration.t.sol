// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISDUSDVaultErrors, ISDUSDVaultEvents} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {SDUSDCommon} from "../SDUSDCommon.t.sol";

contract SDUSD_SetRewardDuration_Test is SDUSDCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        vault.setRewardDuration(8 days);
    }

    function test_ActivePeriodUpdatePreservesCurrentAccountingRateAndReleaseTrajectory() public {
        uint256 principal = vault.totalAssets();
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 4);
        uint256 oldStart = vault.periodStart();
        uint256 oldFinish = vault.rewardPeriodFinish();
        uint256 oldRewards = vault.rewardsForPeriod();
        uint256 oldLockedRewards = vault.lockedRewardsRemaining();
        uint256 oldTotalAssets = vault.totalAssets();
        uint256 oldAccountedAssets = vault.accountedAssets();
        uint256 oldSupply = vault.totalSupply();
        uint256 oldExchangeRate = _exchangeRate();
        uint256 newDuration = 8 days;

        vm.expectEmit(false, false, false, true, address(vault));
        emit ISDUSDVaultEvents.RewardDurationUpdated(REWARD_DURATION, newDuration);
        vm.prank(ADMIN);
        vault.setRewardDuration(newDuration);

        assertEq(vault.rewardDuration(), newDuration);
        assertEq(vault.periodStart(), oldStart);
        assertEq(vault.rewardPeriodFinish(), oldFinish);
        assertEq(vault.rewardsForPeriod(), oldRewards);
        assertEq(vault.lockedRewardsRemaining(), oldLockedRewards);
        assertEq(vault.totalAssets(), oldTotalAssets);
        assertEq(vault.accountedAssets(), oldAccountedAssets);
        assertEq(vault.totalSupply(), oldSupply);
        assertEq(_exchangeRate(), oldExchangeRate);

        // The active period continues to use its original seven-day duration after the configuration update.
        vm.warp(oldStart + REWARD_DURATION / 2);
        uint256 expectedUnlocked = REWARD_AMOUNT / 2;
        uint256 expectedTotalAssets = principal + expectedUnlocked;

        assertEq(vault.periodStart(), oldStart);
        assertEq(vault.rewardPeriodFinish(), oldFinish);
        assertEq(vault.lockedRewardsRemaining(), REWARD_AMOUNT - expectedUnlocked);
        assertEq(vault.totalAssets(), expectedTotalAssets);
        assertEq(
            _exchangeRate(),
            Math.mulDiv(expectedTotalAssets + 1, EXCHANGE_RATE_SCALE, oldSupply + 1),
            "current exchange rate must follow the original release duration"
        );
    }

    function test_ActivePeriodUpdateAppliesToNextPeriodWithoutExchangeRateSpike() public {
        _notifyRewards(REWARD_AMOUNT);
        uint256 oldFinish = vault.rewardPeriodFinish();
        uint256 newDuration = 8 days;

        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        vm.prank(ADMIN);
        vault.setRewardDuration(newDuration);

        vm.warp(oldFinish);
        uint256 assetsBeforeNextPeriod = vault.totalAssets();
        uint256 supplyBeforeNextPeriod = vault.totalSupply();
        uint256 rateBeforeNextPeriod = _exchangeRate();
        uint256 nextReward = 10 ether;
        _notifyRewards(nextReward);

        assertEq(vault.periodStart(), oldFinish);
        assertEq(vault.rewardPeriodFinish(), oldFinish + newDuration);
        assertEq(vault.totalAssets(), assetsBeforeNextPeriod);
        assertEq(vault.totalSupply(), supplyBeforeNextPeriod);
        assertEq(_exchangeRate(), rateBeforeNextPeriod, "notifying the next reward must not spike the exchange rate");

        vm.warp(oldFinish + newDuration / 2);
        uint256 expectedTotalAssets = assetsBeforeNextPeriod + nextReward / 2;

        assertEq(vault.lockedRewardsRemaining(), nextReward / 2);
        assertEq(vault.totalAssets(), expectedTotalAssets);
        assertEq(
            _exchangeRate(),
            Math.mulDiv(expectedTotalAssets + 1, EXCHANGE_RATE_SCALE, supplyBeforeNextPeriod + 1),
            "next exchange-rate trajectory must use the new duration"
        );
    }

    function test_RevertWhen_DurationIsBelowMinimum() public {
        uint256 minimum = vault.MIN_REWARD_DURATION();
        vm.prank(ADMIN);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDInvalidRewardDuration.selector);
        vault.setRewardDuration(minimum - 1);
    }

    function test_RevertWhen_DurationIsAboveMaximum() public {
        uint256 maximum = vault.MAX_REWARD_DURATION();
        vm.prank(ADMIN);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDInvalidRewardDuration.selector);
        vault.setRewardDuration(maximum + 1);
    }

    function test_RevertWhen_DurationEqualsCurrentDuration() public {
        vm.prank(ADMIN);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNoStateChange.selector);
        vault.setRewardDuration(REWARD_DURATION);
    }

    function test_UpdatesDurationWithoutChangingCompletedPeriodAndAppliesToNextPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        uint256 oldStart = vault.periodStart();
        uint256 oldFinish = vault.rewardPeriodFinish();
        uint256 oldRewards = vault.rewardsForPeriod();
        uint256 newDuration = 8 days;

        vm.expectEmit(false, false, false, true, address(vault));
        emit ISDUSDVaultEvents.RewardDurationUpdated(REWARD_DURATION, newDuration);
        vm.prank(ADMIN);
        vault.setRewardDuration(newDuration);

        assertEq(vault.rewardDuration(), newDuration);
        assertEq(vault.periodStart(), oldStart);
        assertEq(vault.rewardPeriodFinish(), oldFinish);
        assertEq(vault.rewardsForPeriod(), oldRewards);

        _notifyRewards(10 ether);
        assertEq(vault.rewardPeriodFinish(), vault.periodStart() + newDuration);
    }

    function test_AllowsUpdateExactlyAtRewardPeriodFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        vm.prank(ADMIN);
        vault.setRewardDuration(8 days);
        assertEq(vault.rewardDuration(), 8 days);
    }

    function test_AllowsMinimumDuration() public {
        uint256 minimum = vault.MIN_REWARD_DURATION();
        vm.prank(ADMIN);
        vault.setRewardDuration(minimum);
        assertEq(vault.rewardDuration(), minimum);
    }

    function test_AllowsMaximumDuration() public {
        uint256 maximum = vault.MAX_REWARD_DURATION();
        vm.prank(ADMIN);
        vault.setRewardDuration(maximum);
        assertEq(vault.rewardDuration(), maximum);
    }
}
