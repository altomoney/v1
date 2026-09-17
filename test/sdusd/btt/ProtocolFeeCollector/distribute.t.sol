// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {ISDUSDVaultErrors} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {
    FeeSourceType,
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_Distribute_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_PausedBeforeHarvesting() public {
        uint256 feeAmount = _generateFlashFees(100 ether);
        _pause();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        collector.distribute();

        assertEq(dusd.balanceOf(address(flashMinter)), feeAmount);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_ZeroPostHarvestBalanceSkipsVaultChecksTransfersAndNotificationAndEmitsZeroAmounts() public {
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.recordLogs();
        vm.prank(USER);
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IERC20.Transfer.selector, address(dusd)), 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 1);
        _assertDistributedEvent(logs, 0, 0, 0);
        assertEq(dusd.balanceOf(TREASURY), 0);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore);
        assertEq(sdusdVault.rewardsForPeriod(), 0);
        assertEq(sdusdVault.rewardPeriodFinish(), 0);
    }

    function test_ZeroRewardsBpsHarvestsAndTransfersAllDusdToTreasuryWithoutVault() public {
        uint256 directBalance = 101 ether;
        uint256 flashFees = _generateFlashFees(100 ether);
        uint256 collected = directBalance + flashFees;
        _setRewardsBps(0);
        dusd.mint(address(collector), directBalance);
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertDistributedEvent(logs, collected, collected, 0);
        assertEq(dusd.balanceOf(TREASURY), collected);
        assertEq(dusd.balanceOf(address(flashMinter)), 0);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore);
        assertEq(sdusdVault.rewardsForPeriod(), 0);
        assertEq(sdusdVault.rewardPeriodFinish(), 0);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_AnyCallerCanDistributeZeroRewardsBpsDuringActiveRewardPeriod() public {
        _startRewardPeriod(400 ether);
        _setRewardsBps(0);
        uint256 collected = 10 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 rewardsForPeriodBefore = sdusdVault.rewardsForPeriod();
        uint256 rewardPeriodFinishBefore = sdusdVault.rewardPeriodFinish();

        vm.prank(USER);
        collector.distribute();

        assertEq(dusd.balanceOf(TREASURY), treasuryBalanceBefore + collected);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(sdusdVault.rewardsForPeriod(), rewardsForPeriodBefore);
        assertEq(sdusdVault.rewardPeriodFinish(), rewardPeriodFinishBefore);
        assertEq(dusd.allowance(address(collector), address(sdusdVault)), 0);
    }

    function test_NonzeroRewardsBpsThatRoundsRewardToZeroSkipsMinimumAndVaultChecks() public {
        uint256 collected = 1;
        dusd.mint(address(collector), collected);

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertDistributedEvent(logs, collected, collected, 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.DistributionDeferred.selector, address(collector)), 0);
        assertEq(dusd.balanceOf(TREASURY), collected);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(sdusdVault.rewardsForPeriod(), 0);
        assertEq(sdusdVault.rewardPeriodFinish(), 0);
    }

    function test_PositiveRewardBelowMinimumRetainsEntireHarvestedBalanceAndDefersWithoutVaultChecks() public {
        uint256 collected = _generateFlashFees(10_000 ether);
        uint256 rewardAmount = collected * INITIAL_REWARDS_BPS / collector.PERCENTAGE_PRECISION();
        assertGt(rewardAmount, 0);
        assertLt(rewardAmount, INITIAL_MINIMUM_REWARD_AMOUNT);
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertDistributionDeferredEvent(logs, collected, rewardAmount, INITIAL_MINIMUM_REWARD_AMOUNT);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Distributed.selector, address(collector)), 0);
        assertEq(dusd.balanceOf(address(flashMinter)), 0);
        assertEq(dusd.balanceOf(address(collector)), collected);
        assertEq(dusd.balanceOf(TREASURY), 0);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore);
        assertEq(sdusdVault.rewardsForPeriod(), 0);
    }

    function test_DeferredBalanceAndLaterHarvestAccumulateUntilMinimumIsMet() public {
        uint256 firstHarvest = _generateFlashFees(10_000 ether);
        collector.distribute();
        assertEq(dusd.balanceOf(address(collector)), firstHarvest);

        _setSdusdVault();
        uint256 secondHarvest = _generateFlashFees(24_000 ether);
        uint256 collected = firstHarvest + secondHarvest;
        uint256 rewardAmount = collected * INITIAL_REWARDS_BPS / collector.PERCENTAGE_PRECISION();
        uint256 treasuryAmount = collected - rewardAmount;
        assertGe(rewardAmount, INITIAL_MINIMUM_REWARD_AMOUNT);

        collector.distribute();

        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(dusd.balanceOf(TREASURY), treasuryAmount);
        assertEq(sdusdVault.rewardsForPeriod(), rewardAmount);
    }

    function test_BelowMinimumDefersWithoutCheckingActiveRewardPeriod() public {
        _startRewardPeriod(400 ether);
        uint256 rewardPeriodFinishBefore = sdusdVault.rewardPeriodFinish();
        uint256 rewardsForPeriodBefore = sdusdVault.rewardsForPeriod();
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 collected = _generateFlashFees(10_000 ether);
        uint256 rewardAmount = collected * INITIAL_REWARDS_BPS / collector.PERCENTAGE_PRECISION();

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertDistributionDeferredEvent(logs, collected, rewardAmount, INITIAL_MINIMUM_REWARD_AMOUNT);
        assertEq(dusd.balanceOf(address(collector)), collected);
        assertEq(dusd.balanceOf(TREASURY), treasuryBalanceBefore);
        assertEq(sdusdVault.rewardsForPeriod(), rewardsForPeriodBefore);
        assertEq(sdusdVault.rewardPeriodFinish(), rewardPeriodFinishBefore);
    }

    function test_RevertWhen_SdusdVaultIsNotSetAndRewardMeetsMinimum() public {
        uint256 collected = 400 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorSdusdNotSet.selector);
        collector.distribute();

        _assertFailedDistributionState(
            collected, treasuryBalanceBefore, vaultBalanceBefore, accountedAssetsBefore, 0, 0
        );
    }

    function test_RevertWhen_RewardPeriodHasNotFinishedAndLeavesDistributionStateUnchanged() public {
        _startRewardPeriod(400 ether);
        uint256 collected = 400 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();
        uint256 rewardsForPeriodBefore = sdusdVault.rewardsForPeriod();
        uint256 rewardPeriodFinishBefore = sdusdVault.rewardPeriodFinish();

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorRewardPeriodNotFinished.selector);
        collector.distribute();

        _assertFailedDistributionState(
            collected,
            treasuryBalanceBefore,
            vaultBalanceBefore,
            accountedAssetsBefore,
            rewardsForPeriodBefore,
            rewardPeriodFinishBefore
        );
    }

    function test_RevertWhen_SdusdVaultIsPausedAndLeavesDistributionStateUnchanged() public {
        _setSdusdVault();
        vm.prank(PAUSER);
        sdusdVault.pause(PAUSE_TYPE, true);
        uint256 collected = 400 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        collector.distribute();

        _assertFailedDistributionState(
            collected, treasuryBalanceBefore, vaultBalanceBefore, accountedAssetsBefore, 0, 0
        );
    }

    function test_RevertWhen_SdusdVaultIsNotSeededAndLeavesDistributionStateUnchanged() public {
        sdusdVault = _deploySdusdVault(_sdusdInitParams(SEED_SHARES, REWARD_DURATION));
        vm.prank(ADMIN);
        collector.setSdusdVault(address(sdusdVault));

        uint256 collected = 400 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);

        vm.expectRevert(ISDUSDVaultErrors.SDUSDNotSeeded.selector);
        collector.distribute();

        _assertFailedDistributionState(collected, treasuryBalanceBefore, 0, 0, 0, 0);
    }

    function test_RevertWhen_OnlySeedSharesRemainAndLeavesDistributionStateUnchanged() public {
        uint256 userShares = sdusdVault.balanceOf(USER);
        vm.prank(USER);
        sdusdVault.redeem(userShares, USER, USER);
        assertEq(sdusdVault.totalSupply(), SEED_SHARES);

        _setSdusdVault();
        uint256 collected = 400 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectRevert(ISDUSDVaultErrors.SDUSDNoActiveStakers.selector);
        collector.distribute();

        _assertFailedDistributionState(
            collected, treasuryBalanceBefore, vaultBalanceBefore, accountedAssetsBefore, 0, 0
        );
    }

    function test_RevertWhen_CollectorIsNotVaultRewarderAndLeavesDistributionStateUnchanged() public {
        _setSdusdVault();
        vm.prank(ADMIN);
        sdusdVault.setRewarder(USER);
        uint256 collected = 400 ether;
        dusd.mint(address(collector), collected);
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.expectRevert(ISDUSDVaultErrors.SDUSDNotRewarder.selector);
        collector.distribute();

        _assertFailedDistributionState(
            collected, treasuryBalanceBefore, vaultBalanceBefore, accountedAssetsBefore, 0, 0
        );
    }

    function test_RewardEqualToMinimumWithFullRewardsBpsNotifiesAllDusdAndResetsAllowance() public {
        uint256 collected = INITIAL_MINIMUM_REWARD_AMOUNT;
        _setSdusdVault();
        _setRewardsBps(collector.PERCENTAGE_PRECISION());
        dusd.mint(address(collector), collected);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertDistributedEvent(logs, collected, 0, collected);
        assertEq(dusd.balanceOf(TREASURY), 0);
        assertEq(sdusdVault.rewardsForPeriod(), collected);
        assertEq(sdusdVault.accountedAssets(), accountedAssetsBefore + collected);
        assertEq(dusd.balanceOf(address(sdusdVault)), vaultBalanceBefore + collected);
        assertEq(dusd.allowance(address(collector), address(sdusdVault)), 0);
        _assertRewardApprovalSequence(logs, collected);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_AnyCallerCanDistributeAboveMinimumWithIntermediateRewardsBpsAndRoundingDown() public {
        uint256 collected = 401 ether + 7;
        uint256 newRewardsBps = 3_333;
        uint256 expectedRewardAmount = collected * newRewardsBps / collector.PERCENTAGE_PRECISION();
        uint256 expectedTreasuryAmount = collected - expectedRewardAmount;
        _setSdusdVault();
        _setRewardsBps(newRewardsBps);
        dusd.mint(address(collector), collected);
        uint256 vaultBalanceBefore = dusd.balanceOf(address(sdusdVault));
        uint256 accountedAssetsBefore = sdusdVault.accountedAssets();

        vm.recordLogs();
        vm.prank(USER);
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertDistributedEvent(logs, collected, expectedTreasuryAmount, expectedRewardAmount);
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
        _startRewardPeriod(400 ether);
        uint256 previousFinish = sdusdVault.rewardPeriodFinish();
        vm.warp(previousFinish);
        uint256 collected = 400 ether;
        uint256 expectedRewardAmount = collected * INITIAL_REWARDS_BPS / collector.PERCENTAGE_PRECISION();
        dusd.mint(address(collector), collected);

        collector.distribute();

        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(sdusdVault.rewardsForPeriod(), expectedRewardAmount);
        assertEq(sdusdVault.periodStart(), previousFinish);
        assertEq(sdusdVault.rewardPeriodFinish(), previousFinish + REWARD_DURATION);
    }

    function test_AutomaticallyHarvestsEveryConfiguredSourceInOrderAndIncludesFeesInSplit() public {
        _allowBorrowMarket(address(borrowMarket));
        _allowMintMarket(address(mintMarket));
        _allowUsm(address(usm));
        uint256 borrowFees = 500 ether;
        _supplyBorrowMarket(borrowFees);
        uint256 mintFees = _generateMintMarketFees(1_000 ether);
        uint256 usmFees = _generateUsmFees(10_000e6);
        uint256 flashFees = _generateFlashFees(10_000 ether);
        uint256 collected = borrowFees + mintFees + usmFees + flashFees;
        uint256 rewardAmount = collected * INITIAL_REWARDS_BPS / collector.PERCENTAGE_PRECISION();
        uint256 treasuryAmount = collected - rewardAmount;
        _setSdusdVault();

        vm.recordLogs();
        vm.prank(USER);
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        FeeSourceType[] memory expectedTypes = new FeeSourceType[](4);
        expectedTypes[0] = FeeSourceType.BORROW_MARKET;
        expectedTypes[1] = FeeSourceType.MINT_MARKET;
        expectedTypes[2] = FeeSourceType.USM;
        expectedTypes[3] = FeeSourceType.FLASH_MINTER;
        address[] memory expectedSources = new address[](4);
        expectedSources[0] = address(borrowMarket);
        expectedSources[1] = address(mintMarket);
        expectedSources[2] = address(usm);
        expectedSources[3] = address(flashMinter);
        uint256[] memory expectedAmounts = new uint256[](4);
        expectedAmounts[0] = borrowFees;
        expectedAmounts[1] = mintFees;
        expectedAmounts[2] = usmFees;
        expectedAmounts[3] = flashFees;
        _assertHarvestSequence(logs, expectedTypes, expectedSources, expectedAmounts);
        _assertDistributedEvent(logs, collected, treasuryAmount, rewardAmount);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(dusd.balanceOf(TREASURY), treasuryAmount);
        assertEq(sdusdVault.rewardsForPeriod(), rewardAmount);
    }

    function test_AutomaticallyEmitsHarvestedForEveryValidZeroFeeSource() public {
        _allowBorrowMarket(address(borrowMarket));
        _allowMintMarket(address(mintMarket));
        _allowUsm(address(usm));

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        FeeSourceType[] memory expectedTypes = new FeeSourceType[](4);
        expectedTypes[0] = FeeSourceType.BORROW_MARKET;
        expectedTypes[1] = FeeSourceType.MINT_MARKET;
        expectedTypes[2] = FeeSourceType.USM;
        expectedTypes[3] = FeeSourceType.FLASH_MINTER;
        address[] memory expectedSources = new address[](4);
        expectedSources[0] = address(borrowMarket);
        expectedSources[1] = address(mintMarket);
        expectedSources[2] = address(usm);
        expectedSources[3] = address(flashMinter);
        uint256[] memory expectedAmounts = new uint256[](4);
        _assertHarvestSequence(logs, expectedTypes, expectedSources, expectedAmounts);
        _assertDistributedEvent(logs, 0, 0, 0);
    }

    function test_InvalidAndPausedConfiguredSourcesAreSkippedAndLaterSourcesAreHarvested() public {
        _allowBorrowMarket(address(wrongTokenBorrowMarket));
        _allowMintMarket(address(mintMarket));
        _allowUsm(address(usm));
        uint256 usmFees = _generateUsmFees(10_000e6);
        vm.prank(PAUSER);
        mintMarket.pause(PAUSE_TYPE, true);
        _setRewardsBps(0);

        vm.recordLogs();
        collector.distribute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 borrowFailureIndex = _findCollectorEvent(logs, IProtocolFeeCollectorEvents.HarvestingFailed.selector, 0);
        uint256 mintFailureIndex =
            _findCollectorEvent(logs, IProtocolFeeCollectorEvents.HarvestingFailed.selector, borrowFailureIndex + 1);
        uint256 usmIndex = _findHarvestedSource(logs, address(usm));
        uint256 flashIndex = _findHarvestedSource(logs, address(flashMinter));
        assertEq(address(uint160(uint256(logs[borrowFailureIndex].topics[2]))), address(wrongTokenBorrowMarket));
        assertEq(address(uint160(uint256(logs[mintFailureIndex].topics[2]))), address(mintMarket));
        assertLt(borrowFailureIndex, mintFailureIndex);
        assertLt(mintFailureIndex, usmIndex);
        assertLt(usmIndex, flashIndex);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.HarvestingFailed.selector, address(collector)), 2);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 2);
        assertEq(dusd.balanceOf(TREASURY), usmFees);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_RevertFromConfiguredSourceRollsBackEarlierHarvestsAndDistribution() public {
        _allowBorrowMarket(address(borrowMarket));
        uint256 supplyShares = _supplyBorrowMarket(500 ether);
        bytes memory reason = abi.encodeWithSignature("Error(string)", "flash harvest failed");
        vm.mockCallRevert(
            address(flashMinter),
            abi.encodeWithSelector(IStableTokenFacilitator.distributeFeesToFeeRecipient.selector),
            reason
        );

        vm.expectRevert(reason);
        collector.distribute();

        Position memory remainingPosition = borrowMarket.position(address(collector));
        assertEq(remainingPosition.supplyShares, supplyShares);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(dusd.balanceOf(TREASURY), 0);
    }

    function test_RevertWhen_RegistryGetterReverts() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "registry failed");
        vm.mockCallRevert(
            address(marketRegistry), abi.encodeWithSelector(IMarketRegistry.getBorrowMarkets.selector), reason
        );

        vm.expectRevert(reason);
        collector.distribute();
    }

    function _assertFailedDistributionState(
        uint256 collectorBalance,
        uint256 treasuryBalance,
        uint256 vaultBalance,
        uint256 accountedAssets,
        uint256 rewardsForPeriod,
        uint256 rewardPeriodFinish
    ) internal view {
        assertEq(dusd.balanceOf(address(collector)), collectorBalance);
        assertEq(dusd.balanceOf(TREASURY), treasuryBalance);
        assertEq(dusd.balanceOf(address(sdusdVault)), vaultBalance);
        assertEq(sdusdVault.accountedAssets(), accountedAssets);
        assertEq(sdusdVault.rewardsForPeriod(), rewardsForPeriod);
        assertEq(sdusdVault.rewardPeriodFinish(), rewardPeriodFinish);
        assertEq(dusd.allowance(address(collector), address(sdusdVault)), 0);
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

    function _assertDistributedEvent(
        Vm.Log[] memory logs,
        uint256 collected,
        uint256 treasuryAmount,
        uint256 rewardAmount
    ) internal view {
        uint256 index = _findCollectorEvent(logs, IProtocolFeeCollectorEvents.Distributed.selector, 0);
        (uint256 emittedCollected, uint256 emittedTreasuryAmount, uint256 emittedRewardAmount) =
            abi.decode(logs[index].data, (uint256, uint256, uint256));
        assertEq(emittedCollected, collected);
        assertEq(emittedTreasuryAmount, treasuryAmount);
        assertEq(emittedRewardAmount, rewardAmount);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Distributed.selector, address(collector)), 1);
    }

    function _assertDistributionDeferredEvent(
        Vm.Log[] memory logs,
        uint256 collected,
        uint256 rewardAmount,
        uint256 minimumRewardAmount
    ) internal view {
        uint256 index = _findCollectorEvent(logs, IProtocolFeeCollectorEvents.DistributionDeferred.selector, 0);
        (uint256 emittedCollected, uint256 emittedRewardAmount, uint256 emittedMinimumRewardAmount) =
            abi.decode(logs[index].data, (uint256, uint256, uint256));
        assertEq(emittedCollected, collected);
        assertEq(emittedRewardAmount, rewardAmount);
        assertEq(emittedMinimumRewardAmount, minimumRewardAmount);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.DistributionDeferred.selector, address(collector)), 1);
    }

    function _assertHarvestSequence(
        Vm.Log[] memory logs,
        FeeSourceType[] memory expectedTypes,
        address[] memory expectedSources,
        uint256[] memory expectedAmounts
    ) internal view {
        uint256 harvestedIndex;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(collector) || logs[i].topics.length == 0
                    || logs[i].topics[0] != IProtocolFeeCollectorEvents.Harvested.selector
            ) continue;

            assertEq(uint256(logs[i].topics[1]), uint256(expectedTypes[harvestedIndex]));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), expectedSources[harvestedIndex]);
            assertEq(abi.decode(logs[i].data, (uint256)), expectedAmounts[harvestedIndex]);
            harvestedIndex++;
        }
        assertEq(harvestedIndex, expectedTypes.length);
    }

    function _findCollectorEvent(Vm.Log[] memory logs, bytes32 selector, uint256 start)
        internal
        view
        returns (uint256 index)
    {
        for (uint256 i = start; i < logs.length; ++i) {
            if (logs[i].emitter == address(collector) && logs[i].topics.length != 0 && logs[i].topics[0] == selector) {
                return i;
            }
        }
        revert("collector event not found");
    }

    function _findHarvestedSource(Vm.Log[] memory logs, address source) internal view returns (uint256 index) {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(collector) && logs[i].topics.length == 3
                    && logs[i].topics[0] == IProtocolFeeCollectorEvents.Harvested.selector
                    && address(uint160(uint256(logs[i].topics[2]))) == source
            ) return i;
        }
        revert("Harvested source not found");
    }
}
