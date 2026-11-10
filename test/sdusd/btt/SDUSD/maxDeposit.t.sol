// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxDeposit_Test is SDUSDCommon {
    function test_EmptyVaultReturnsSeedAmountOnlyForSeedLock() public {
        vault = _deployVaultWithCap(SEED_SHARES, REWARD_DURATION, 0);

        assertEq(vault.maxDeposit(SEED_LOCK), SEED_SHARES);
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxDeposit(RECEIVER), 0);
        assertEq(vault.maxDeposit(address(0)), 0);
    }

    function test_EmptyVaultReturnsZeroForSeedLockWhenPaused() public {
        _useEmptyVault();
        _pauseVault();

        assertEq(vault.maxDeposit(SEED_LOCK), 0);
    }

    function test_ReturnsZeroForEveryReceiverWhenPaused() public {
        _pauseVault();
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxDeposit(RECEIVER), 0);
        assertEq(vault.maxDeposit(address(0)), 0);
    }

    function test_ReturnsExactRemainingHeadroomForEveryReceiverWhenUnpaused() public view {
        uint256 expected = vault.depositCap() - vault.depositCapUsage();
        assertEq(vault.maxDeposit(USER), expected);
        assertEq(vault.maxDeposit(RECEIVER), expected);
        assertEq(vault.maxDeposit(address(0)), expected);
    }

    function test_ReturnsZeroWhenUsageEqualsCap() public {
        _setDepositCap(vault.depositCapUsage());
        assertEq(vault.maxDeposit(USER), 0);
    }

    function test_ReturnsZeroWithoutUnderflowWhenUsageExceedsCap() public {
        _setDepositCap(vault.depositCapUsage() - 1);
        assertEq(vault.maxDeposit(USER), 0);
    }

    function test_ReleasedRewardsReduceHeadroomButDonationsAndTransfersDoNot() public {
        uint256 expected = vault.maxDeposit(USER);

        _notifyRewards(REWARD_AMOUNT);
        assertEq(vault.maxDeposit(USER), expected);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        expected -= REWARD_AMOUNT / 2;
        _donate(100 ether);
        uint256 transferredShares = vault.balanceOf(USER) / 2;
        vm.prank(USER);
        vault.transfer(RECEIVER, transferredShares);

        assertEq(vault.maxDeposit(USER), expected);
        assertEq(vault.maxDeposit(RECEIVER), expected);
    }

    function test_ReturnsZeroWhenRemainingHeadroomRoundsDownToZeroShares() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        _setDepositCap(vault.depositCapUsage() + 1);

        assertEq(vault.depositCap() - vault.depositCapUsage(), 1);
        assertEq(vault.previewDeposit(1), 0);
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);
    }
}
