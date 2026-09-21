// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {ISDUSDVaultErrors, ISDUSDVaultEvents} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_NotifyRewardAmount_Test is SDUSDCommon {
    function test_RevertWhen_Paused() public {
        _pauseVault();
        vm.prank(address(collector));
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vault.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_RevertWhen_CallerIsNotRewarder() public {
        vm.prank(USER);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNotRewarder.selector);
        vault.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_RevertWhen_PreviousRewardPeriodIsActive() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.prank(address(collector));
        vm.expectRevert(ISDUSDVaultErrors.SDUSDRewardPeriodNotFinished.selector);
        vault.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_RevertWhen_SeedDepositHasNotOccurred() public {
        _useEmptyVault();
        vm.prank(address(collector));
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNotSeeded.selector);
        vault.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_RevertWhen_SeedLockBalanceIsInsufficientEvenIfTotalSupplyExceedsSeedShares() public {
        _useEmptyVault();
        _depositFor(USER, SEED_SHARES + 1);

        assertEq(vault.balanceOf(SEED_LOCK), 0);
        assertGt(vault.totalSupply(), vault.seedShares());

        vm.prank(address(collector));
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNotSeeded.selector);
        vault.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_RevertWhen_OnlySeedSharesRemain() public {
        uint256 userShares = vault.balanceOf(USER);
        vm.prank(USER);
        vault.redeem(userShares, USER, USER);

        assertEq(vault.totalSupply(), SEED_SHARES);
        vm.prank(address(collector));
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNoActiveStakers.selector);
        vault.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_RevertWhen_ExtraShareIsTransferredToLockAndAllUsersExit() public {
        vm.startPrank(USER);
        vault.transfer(SEED_LOCK, 1);
        vault.redeem(vault.balanceOf(USER), USER, USER);
        vm.stopPrank();
        uint256 accountedBefore = vault.accountedAssets();
        dusd.mint(address(collector), REWARD_AMOUNT);
        vm.prank(address(collector));
        dusd.approve(address(vault), REWARD_AMOUNT);

        assertGt(vault.totalSupply(), SEED_SHARES);
        assertEq(vault.totalSupply(), vault.balanceOf(SEED_LOCK));
        vm.prank(address(collector));
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNoActiveStakers.selector);
        vault.notifyRewardAmount(REWARD_AMOUNT);

        assertEq(dusd.balanceOf(address(collector)), REWARD_AMOUNT);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.rewardsForPeriod(), 0);
        assertEq(vault.rewardPeriodFinish(), 0);
    }

    function test_ExtraDepositToLockCannotEnableRepeatedDistributionsWithoutStakers() public {
        _setSdusdVault();
        _setRewardsBps(10_000);
        vm.startPrank(USER);
        vault.redeem(vault.balanceOf(USER), USER, USER);
        dusd.approve(address(vault), 1);
        vault.deposit(1, SEED_LOCK);
        vm.stopPrank();
        dusd.mint(address(collector), 300 ether);

        assertEq(vault.totalSupply(), SEED_SHARES + 1);
        assertEq(vault.totalSupply(), vault.balanceOf(SEED_LOCK));
        for (uint256 i; i < 3; ++i) {
            vm.expectRevert(ISDUSDVaultErrors.SDUSDNoActiveStakers.selector);
            collector.distribute();
            vm.warp(block.timestamp + REWARD_DURATION);
        }

        assertEq(dusd.balanceOf(address(collector)), 300 ether);
        assertEq(dusd.balanceOf(TREASURY), 0);
        assertEq(vault.accountedAssets(), SEED_SHARES + 1);
        assertEq(vault.rewardsForPeriod(), 0);
        assertEq(vault.rewardPeriodFinish(), 0);
    }

    function test_AllowsRewardsWithAdditionalLockedSharesAndLiveSharesRemaining() public {
        uint256 extraLocked = vault.balanceOf(USER) / 2;
        vm.prank(USER);
        vault.transfer(SEED_LOCK, extraLocked);
        uint256 accountedBefore = vault.accountedAssets();

        _notifyRewards(REWARD_AMOUNT);

        assertEq(vault.balanceOf(SEED_LOCK), SEED_SHARES + extraLocked);
        assertGt(vault.totalSupply(), vault.balanceOf(SEED_LOCK));
        assertEq(vault.accountedAssets(), accountedBefore + REWARD_AMOUNT);
        assertEq(vault.rewardsForPeriod(), REWARD_AMOUNT);
        assertEq(vault.rewardPeriodFinish(), block.timestamp + REWARD_DURATION);
    }

    function test_RevertWhen_AmountIsZero() public {
        vm.prank(address(collector));
        vm.expectRevert(ISDUSDVaultErrors.SDUSDZeroAmount.selector);
        vault.notifyRewardAmount(0);
    }

    function test_RevertWhen_AllowanceIsInsufficientAndLeavesStateUnchanged() public {
        dusd.mint(address(collector), REWARD_AMOUNT);
        uint256 accountedBefore = vault.accountedAssets();

        vm.prank(address(collector));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, REWARD_AMOUNT)
        );
        vault.notifyRewardAmount(REWARD_AMOUNT);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.rewardsForPeriod(), 0);
        assertEq(vault.periodStart(), 0);
        assertEq(vault.rewardPeriodFinish(), 0);
    }

    function test_RevertWhen_RewarderBalanceIsInsufficientAndLeavesStateUnchanged() public {
        uint256 accountedBefore = vault.accountedAssets();
        vm.prank(address(collector));
        dusd.approve(address(vault), REWARD_AMOUNT);

        vm.prank(address(collector));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(collector), 0, REWARD_AMOUNT)
        );
        vault.notifyRewardAmount(REWARD_AMOUNT);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.rewardsForPeriod(), 0);
        assertEq(vault.periodStart(), 0);
        assertEq(vault.rewardPeriodFinish(), 0);
    }

    function test_StartsRewardPeriodAndUpdatesAllAccountingWithoutMintingShares() public {
        _setDepositCap(vault.depositCapUsage() - 1);
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 maxDepositBefore = vault.maxDeposit(USER);
        uint256 supplyBefore = vault.totalSupply();
        uint256 userSharesBefore = vault.balanceOf(USER);
        uint256 seedSharesBefore = vault.balanceOf(SEED_LOCK);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(vault));
        uint256 start = block.timestamp;

        assertGt(vault.depositCapUsage(), vault.depositCap());
        assertEq(maxDepositBefore, 0);

        dusd.mint(address(collector), REWARD_AMOUNT);
        vm.prank(address(collector));
        dusd.approve(address(vault), REWARD_AMOUNT);
        vm.expectEmit(false, false, false, true, address(vault));
        emit ISDUSDVaultEvents.RewardAdded(REWARD_AMOUNT, start + REWARD_DURATION);
        vm.prank(address(collector));
        vault.notifyRewardAmount(REWARD_AMOUNT);

        assertEq(dusd.balanceOf(address(vault)), vaultBalanceBefore + REWARD_AMOUNT);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(vault.accountedAssets(), accountedBefore + REWARD_AMOUNT);
        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.maxDeposit(USER), maxDepositBefore);
        assertEq(vault.rewardsForPeriod(), REWARD_AMOUNT);
        assertEq(vault.periodStart(), start);
        assertEq(vault.rewardPeriodFinish(), start + REWARD_DURATION);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(USER), userSharesBefore);
        assertEq(vault.balanceOf(SEED_LOCK), seedSharesBefore);
        assertEq(vault.totalAssets(), accountedBefore);
        _assertExchangeRateUnchanged(exchangeRateBefore);
    }

    function test_AllowsNewPeriodExactlyAtPreviousFinish() public {
        _notifyRewards(REWARD_AMOUNT);
        uint256 previousFinish = vault.rewardPeriodFinish();
        vm.warp(previousFinish);
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        _notifyRewards(10 ether);

        assertEq(vault.periodStart(), previousFinish);
        assertEq(vault.rewardPeriodFinish(), previousFinish + REWARD_DURATION);
        _assertExchangeRateUnchanged(exchangeRateBefore);
    }

    function test_ReplacesCompletedPeriodStateAndPreservesPreviouslyAccountedRewards() public {
        uint256 accountedBefore = vault.accountedAssets();
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        _notifyRewards(10 ether);

        assertEq(vault.accountedAssets(), accountedBefore + REWARD_AMOUNT + 10 ether);
        assertEq(vault.rewardsForPeriod(), 10 ether);
        assertEq(vault.lockedRewardsRemaining(), 10 ether);
        _assertExchangeRateUnchanged(exchangeRateBefore);
    }
}
