// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxRedeem_Test is SDUSDCommon {
    function test_ReturnsZeroWhenOwnerHasNoShares() public view {
        assertEq(vault.maxRedeem(RECEIVER), 0);
    }

    function test_ReturnsFullOwnerShareBalance() public view {
        assertEq(vault.maxRedeem(USER), vault.balanceOf(USER));
    }

    function test_RemainsOwnerShareBalanceDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        assertEq(vault.maxRedeem(USER), vault.balanceOf(USER));
    }

    function test_RemainsOwnerShareBalanceWhileFrozen() public {
        _freezeVault();
        assertEq(vault.maxRedeem(USER), vault.balanceOf(USER));
    }

    function test_RemainsOwnerShareBalanceAfterRawDonation() public {
        _donate(100 ether);
        assertEq(vault.maxRedeem(USER), vault.balanceOf(USER));
    }
}
