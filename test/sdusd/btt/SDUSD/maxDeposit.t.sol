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

    function test_ReturnsMaximumUintForEveryReceiverWhenUnpaused() public view {
        assertEq(vault.maxDeposit(USER), type(uint256).max);
        assertEq(vault.maxDeposit(RECEIVER), type(uint256).max);
        assertEq(vault.maxDeposit(address(0)), type(uint256).max);
    }
}
