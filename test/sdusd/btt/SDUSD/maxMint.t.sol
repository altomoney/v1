// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxMint_Test is SDUSDCommon {
    function test_ReturnsZeroForEveryReceiverWhenPaused() public {
        _pauseVault();
        assertEq(vault.maxMint(USER), 0);
        assertEq(vault.maxMint(RECEIVER), 0);
        assertEq(vault.maxMint(address(0)), 0);
    }

    function test_ReturnsMaximumUintForEveryReceiverWhenUnpaused() public view {
        assertEq(vault.maxMint(USER), type(uint256).max);
        assertEq(vault.maxMint(RECEIVER), type(uint256).max);
        assertEq(vault.maxMint(address(0)), type(uint256).max);
    }
}
