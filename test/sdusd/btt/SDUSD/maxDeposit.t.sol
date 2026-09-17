// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxDeposit_Test is SDUSDCommon {
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

    function test_RewardsDonationsAndShareTransfersDoNotReduceAssetHeadroom() public {
        uint256 expected = vault.maxDeposit(USER);

        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        _donate(100 ether);
        uint256 transferredShares = vault.balanceOf(USER) / 2;
        vm.prank(USER);
        vault.transfer(RECEIVER, transferredShares);

        assertEq(vault.maxDeposit(USER), expected);
        assertEq(vault.maxDeposit(RECEIVER), expected);
    }
}
