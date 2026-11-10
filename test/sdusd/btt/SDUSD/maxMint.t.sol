// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxMint_Test is SDUSDCommon {
    function test_EmptyVaultReturnsSeedSharesOnlyForSeedLock() public {
        vault = _deployVaultWithCap(SEED_SHARES, REWARD_DURATION, 0);

        assertEq(vault.maxMint(SEED_LOCK), SEED_SHARES);
        assertEq(vault.maxMint(USER), 0);
        assertEq(vault.maxMint(RECEIVER), 0);
        assertEq(vault.maxMint(address(0)), 0);
    }

    function test_EmptyVaultReturnsZeroForSeedLockWhenPaused() public {
        _useEmptyVault();
        _pauseVault();

        assertEq(vault.maxMint(SEED_LOCK), 0);
    }

    function test_ReturnsZeroForEveryReceiverWhenPaused() public {
        _pauseVault();
        assertEq(vault.maxMint(USER), 0);
        assertEq(vault.maxMint(RECEIVER), 0);
        assertEq(vault.maxMint(address(0)), 0);
    }

    function test_ReturnsRemainingHeadroomConvertedToSharesForEveryReceiver() public view {
        uint256 headroom = vault.depositCap() - vault.depositCapUsage();
        uint256 expected = Math.mulDiv(headroom, vault.totalSupply() + 1, vault.totalAssets() + 1, Math.Rounding.Floor);

        assertEq(vault.maxMint(USER), expected);
        assertEq(vault.maxMint(RECEIVER), expected);
        assertEq(vault.maxMint(address(0)), expected);
    }

    function test_ReturnsZeroWhenUsageEqualsCap() public {
        _setDepositCap(vault.depositCapUsage());
        assertEq(vault.maxMint(USER), 0);
    }

    function test_ReturnsZeroWithoutUnderflowWhenUsageExceedsCap() public {
        _setDepositCap(vault.depositCapUsage() - 1);
        assertEq(vault.maxMint(USER), 0);
    }

    function test_RewardVestingReducesAssetHeadroomAndShareMaximum() public {
        uint256 headroomBefore = vault.maxDeposit(USER);
        uint256 sharesBefore = vault.maxMint(USER);

        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);

        uint256 headroomAfter = headroomBefore - REWARD_AMOUNT / 2;
        uint256 expected =
            Math.mulDiv(headroomAfter, vault.totalSupply() + 1, vault.totalAssets() + 1, Math.Rounding.Floor);
        assertEq(vault.maxDeposit(USER), headroomAfter);
        assertEq(vault.maxMint(USER), expected);
        assertLt(vault.maxMint(USER), sharesBefore);
    }

    function test_ReturnsZeroWhenPositiveAssetHeadroomRoundsDownToZeroShares() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        _setDepositCap(vault.depositCapUsage() + 1);

        assertEq(vault.depositCap() - vault.depositCapUsage(), 1);
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);
    }
}
