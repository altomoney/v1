// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ISDUSDVaultEvents} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_RecoverUnaccountedAssets_Test is SDUSDCommon {
    uint256 internal constant DONATION = 11 ether;

    function test_RevertWhen_CallerIsNotOwner() public {
        _donate(DONATION);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(vault));

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        vault.recoverUnaccountedAssets();

        assertEq(dusd.balanceOf(address(vault)), vaultBalanceBefore);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_ZeroUnaccountedBalanceReturnsZeroWithoutTransferOrEvent() public {
        uint256 vaultBalanceBefore = dusd.balanceOf(address(vault));
        uint256 accountedAssetsBefore = vault.accountedAssets();

        vm.recordLogs();
        vm.prank(ADMIN);
        uint256 recoveredAssets = vault.recoverUnaccountedAssets();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(recoveredAssets, 0);
        assertEq(logs.length, 0);
        assertEq(dusd.balanceOf(address(vault)), vaultBalanceBefore);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(vault.accountedAssets(), accountedAssetsBefore);
    }

    function test_OwnerRecoversExactlyBalanceMinusAccountedAssetsToRewarder() public {
        _donate(DONATION);
        uint256 accountedAssetsBefore = vault.accountedAssets();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 maxDepositBefore = vault.maxDeposit(USER);
        uint256 rewarderBalanceBefore = dusd.balanceOf(address(collector));

        assertEq(dusd.balanceOf(address(vault)) - accountedAssetsBefore, DONATION);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ISDUSDVaultEvents.UnaccountedAssetsRecovered(address(collector), DONATION);

        vm.prank(ADMIN);
        uint256 recoveredAssets = vault.recoverUnaccountedAssets();

        assertEq(recoveredAssets, DONATION);
        assertEq(dusd.balanceOf(address(vault)), accountedAssetsBefore);
        assertEq(dusd.balanceOf(address(collector)), rewarderBalanceBefore + DONATION);
        assertEq(vault.accountedAssets(), accountedAssetsBefore);
        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.maxDeposit(USER), maxDepositBefore);
    }

    function test_ActiveRewardRecoversOnlyDonationAndPreservesLockedRewards() public {
        _notifyRewards(REWARD_AMOUNT);
        _donate(DONATION);
        uint256 accountedAssetsBefore = vault.accountedAssets();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 lockedRewardsBefore = vault.lockedRewardsRemaining();
        uint256 rewardsForPeriodBefore = vault.rewardsForPeriod();
        uint256 periodStartBefore = vault.periodStart();
        uint256 rewardPeriodFinishBefore = vault.rewardPeriodFinish();

        assertLt(totalAssetsBefore, accountedAssetsBefore);
        assertEq(dusd.balanceOf(address(vault)) - accountedAssetsBefore, DONATION);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ISDUSDVaultEvents.UnaccountedAssetsRecovered(address(collector), DONATION);

        vm.prank(ADMIN);
        uint256 recoveredAssets = vault.recoverUnaccountedAssets();

        assertEq(recoveredAssets, DONATION);
        assertEq(dusd.balanceOf(address(vault)), accountedAssetsBefore);
        assertEq(dusd.balanceOf(address(collector)), DONATION);
        assertEq(vault.accountedAssets(), accountedAssetsBefore);
        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.lockedRewardsRemaining(), lockedRewardsBefore);
        assertEq(vault.rewardsForPeriod(), rewardsForPeriodBefore);
        assertEq(vault.periodStart(), periodStartBefore);
        assertEq(vault.rewardPeriodFinish(), rewardPeriodFinishBefore);
    }

    function test_RecoveryUsesCurrentConfiguredRewarderAsFixedReceiver() public {
        vm.prank(ADMIN);
        vault.setRewarder(NEW_REWARDER);
        _donate(DONATION);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ISDUSDVaultEvents.UnaccountedAssetsRecovered(NEW_REWARDER, DONATION);

        vm.prank(ADMIN);
        vault.recoverUnaccountedAssets();

        assertEq(dusd.balanceOf(NEW_REWARDER), DONATION);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(dusd.balanceOf(address(vault)), vault.accountedAssets());
    }

    function test_OwnerCanRecoverWhileVaultIsPaused() public {
        _donate(DONATION);
        _pauseVault();

        vm.prank(ADMIN);
        uint256 recoveredAssets = vault.recoverUnaccountedAssets();

        assertEq(recoveredAssets, DONATION);
        assertEq(dusd.balanceOf(address(collector)), DONATION);
        assertEq(dusd.balanceOf(address(vault)), vault.accountedAssets());
    }
}
