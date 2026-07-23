// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_TotalAssets_Test is SDUSDCommon {
    function test_ReturnsAccountedAssetsWhenNoRewardPeriodStarted() public view {
        assertEq(vault.totalAssets(), vault.accountedAssets());
    }

    function test_ExcludesEntireRewardAtPeriodStart() public {
        uint256 assetsBefore = vault.totalAssets();
        _notifyRewards(REWARD_AMOUNT);

        assertEq(vault.totalAssets(), assetsBefore);
        assertEq(vault.lockedRewardsRemaining(), REWARD_AMOUNT);
    }

    function test_ReturnsAccountedAssetsMinusLockedRewardsDuringPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);

        assertEq(vault.totalAssets(), vault.accountedAssets() - vault.lockedRewardsRemaining());
    }

    function test_ExchangeRateDoesNotSpikeThenIncreasesIntegerLinearlyAndStopsAtFinish() public {
        uint256 principal = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        uint256 exchangeRateBefore = _exchangeRate();
        _notifyRewards(REWARD_AMOUNT);
        uint256 start = vault.periodStart();

        assertEq(_exchangeRate(), exchangeRateBefore);

        uint256 previousRate = exchangeRateBefore;
        for (uint256 quarter = 1; quarter <= 3; ++quarter) {
            uint256 elapsed = REWARD_DURATION * quarter / 4;
            vm.warp(start + elapsed);
            uint256 expectedUnlocked = Math.mulDiv(REWARD_AMOUNT, elapsed, REWARD_DURATION);
            uint256 expectedTotalAssets = principal + expectedUnlocked;
            uint256 expectedRate = Math.mulDiv(expectedTotalAssets + 1, EXCHANGE_RATE_SCALE, supply + 1);

            assertEq(vault.totalAssets(), expectedTotalAssets);
            assertEq(_exchangeRate(), expectedRate);
            assertGt(_exchangeRate(), previousRate);
            previousRate = expectedRate;
        }

        vm.warp(vault.rewardPeriodFinish());
        uint256 finishRate = Math.mulDiv(principal + REWARD_AMOUNT + 1, EXCHANGE_RATE_SCALE, supply + 1);
        assertEq(vault.totalAssets(), principal + REWARD_AMOUNT);
        assertEq(_exchangeRate(), finishRate);
        assertGt(finishRate, previousRate);

        vm.warp(vault.rewardPeriodFinish() + 1 days);
        assertEq(_exchangeRate(), finishRate);
    }

    function test_IncludesAllButFinalLockedFractionImmediatelyBeforeFinish() public {
        uint256 principal = vault.totalAssets();
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.rewardPeriodFinish() - 1);

        assertEq(vault.totalAssets(), principal + REWARD_AMOUNT - vault.lockedRewardsRemaining());
        assertGt(vault.lockedRewardsRemaining(), 0);
    }

    function test_ReturnsAccountedAssetsAtRewardPeriodFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        assertEq(vault.totalAssets(), vault.accountedAssets());
    }

    function test_ReturnsAccountedAssetsAfterRewardPeriodFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.rewardPeriodFinish() + 1);
        assertEq(vault.totalAssets(), vault.accountedAssets());
    }

    function test_RawDonationDoesNotChangeAccountingOrTotalAssets() public {
        uint256 exchangeRateBefore = _exchangeRate();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 totalBefore = vault.totalAssets();
        _donate(10 ether);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.totalAssets(), totalBefore);
        assertEq(dusd.balanceOf(address(vault)), accountedBefore + 10 ether);
        assertEq(_exchangeRate(), exchangeRateBefore);
    }

    function test_RawDonationDuringActivePeriodDoesNotBypassLinearReleaseOrChangeExchangeRate() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 exchangeRateBefore = _exchangeRate();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 lockedBefore = vault.lockedRewardsRemaining();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 startBefore = vault.periodStart();
        uint256 finishBefore = vault.rewardPeriodFinish();

        _donate(10 ether);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.lockedRewardsRemaining(), lockedBefore);
        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.periodStart(), startBefore);
        assertEq(vault.rewardPeriodFinish(), finishBefore);
        assertEq(_exchangeRate(), exchangeRateBefore);
    }
}
