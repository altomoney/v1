// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_Distribute_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_Paused() public {
        _pause();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        collector.distribute();
    }

    function test_RevertWhen_SdusdVaultIsNotSet() public {
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorSdusdNotSet.selector);
        collector.distribute();
    }

    function test_RevertWhen_RewardPeriodHasNotFinished() public {
        _startRewardPeriod(100 ether);
        dusd.mint(address(collector), 10 ether);

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorRewardPeriodNotFinished.selector);
        collector.distribute();
    }

    function test_ZeroBalanceSkipsTransfersAndNotificationAndEmitsZeroAmounts() public {
        _setSdusdVault();
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.Distributed(0, 0, 0);

        vm.recordLogs();
        vm.prank(USER);
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IERC20.Transfer.selector, address(dusd)), 0);
        assertEq(dusd.balanceOf(TREASURY), 0);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore);
        assertEq(sdusdVault.rewardsForPeriod(), 0);
        assertEq(sdusdVault.rewardPeriodFinish(), 0);
    }

    function test_ZeroRewardsBpsTransfersAllDusdToTreasuryWithoutNotification() public {
        uint256 collected = 101 ether;
        _setSdusdVault();
        _setRewardsBps(0);
        dusd.mint(address(collector), collected);
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.Distributed(collected, collected, 0);

        collector.distribute();

        assertEq(dusd.balanceOf(TREASURY), collected);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore);
        assertEq(sdusdVault.rewardsForPeriod(), 0);
        assertEq(sdusdVault.rewardPeriodFinish(), 0);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_FullRewardsBpsNotifiesAllDusdAndResetsAllowance() public {
        uint256 collected = 99 ether;
        _setSdusdVault();
        _setRewardsBps(collector.PERCENTAGE_PRECISION());
        dusd.mint(address(collector), collected);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.Distributed(collected, 0, collected);

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(dusd.balanceOf(TREASURY), 0);
        assertEq(sdusdVault.rewardsForPeriod(), collected);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore + collected);
        assertEq(dusd.balanceOf(address(sdusdVault)), vaultBalanceBefore + collected);
        assertEq(dusd.allowance(address(collector), address(sdusdVault)), 0);
        _assertRewardApprovalSequence(logs, collected);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_IntermediateRewardsBpsRoundsDownSplitsAndEmits() public {
        uint256 collected = 101;
        uint256 newRewardsBps = 3_333;
        uint256 expectedRewardAmount = 33;
        uint256 expectedTreasuryAmount = 68;
        _setSdusdVault();
        _setRewardsBps(newRewardsBps);
        dusd.mint(address(collector), collected);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.Distributed(collected, expectedTreasuryAmount, expectedRewardAmount);

        vm.recordLogs();
        vm.prank(USER);
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(expectedRewardAmount + expectedTreasuryAmount, collected);
        assertEq(dusd.balanceOf(TREASURY), expectedTreasuryAmount);
        assertEq(sdusdVault.rewardsForPeriod(), expectedRewardAmount);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore + expectedRewardAmount);
        assertEq(dusd.balanceOf(address(sdusdVault)), vaultBalanceBefore + expectedRewardAmount);
        assertEq(dusd.allowance(address(collector), address(sdusdVault)), 0);
        _assertRewardApprovalSequence(logs, expectedRewardAmount);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_AllowsDistributionWhenTimestampEqualsRewardPeriodFinish() public {
        _startRewardPeriod(100 ether);
        uint256 previousFinish = sdusdVault.rewardPeriodFinish();
        vm.warp(previousFinish);
        uint256 collected = 10 ether;
        uint256 expectedRewardAmount = collected * INITIAL_REWARDS_BPS / collector.PERCENTAGE_PRECISION();
        dusd.mint(address(collector), collected);

        collector.distribute();

        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(sdusdVault.rewardsForPeriod(), expectedRewardAmount);
        assertEq(sdusdVault.periodStart(), previousFinish);
        assertEq(sdusdVault.rewardPeriodFinish(), previousFinish + REWARD_DURATION);
    }

    function _assertRewardApprovalSequence(Vm.Log[] memory logs, uint256 rewardAmount) internal view {
        uint256 approvalIndex;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(dusd) && logs[i].topics.length == 3
                    && logs[i].topics[0] == IERC20.Approval.selector
                    && address(uint160(uint256(logs[i].topics[1]))) == address(collector)
                    && address(uint160(uint256(logs[i].topics[2]))) == address(sdusdVault)
            ) {
                uint256 approvalAmount = abi.decode(logs[i].data, (uint256));
                assertEq(approvalAmount, approvalIndex == 0 ? rewardAmount : 0);
                approvalIndex++;
            }
        }
        assertEq(approvalIndex, 2);
    }
}
