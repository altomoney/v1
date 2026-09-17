// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxMint_Test is SDUSDCommon {
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

    function test_RewardVestingChangesShareMaximumButNotAssetHeadroom() public {
        uint256 headroomBefore = vault.maxDeposit(USER);
        uint256 sharesBefore = vault.maxMint(USER);

        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);

        uint256 expected =
            Math.mulDiv(headroomBefore, vault.totalSupply() + 1, vault.totalAssets() + 1, Math.Rounding.Floor);
        assertEq(vault.maxDeposit(USER), headroomBefore);
        assertEq(vault.maxMint(USER), expected);
        assertLt(vault.maxMint(USER), sharesBefore);
    }
}
