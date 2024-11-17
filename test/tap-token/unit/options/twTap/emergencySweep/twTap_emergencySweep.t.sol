// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {twTapBaseTest, TwTAP} from "../twTapBaseTest.sol";
import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";

contract twTap_emergencySweep is twTapBaseTest {
    function test_RevertWhen_EmergencyCooldownNotReached() external {
        // it should revert
        vm.startPrank(adminAddr);
        vm.expectRevert(ITWTAPv2.EmergencySweepCooldownNotReached.selector);
        twTap.emergencySweep(address(tapOFT));
    }

    function test_RevertWhen_NotOwner() external {
        // it should revert
        vm.startPrank(adminAddr);
        twTap.setEmergencySweepCooldown(0);
        twTap.activateEmergencySweep();
        vm.stopPrank();
        vm.expectRevert("Ownable: caller is not the owner");
        twTap.emergencySweep(address(tapOFT));
    }

    function test_ShouldSweepTheLocks() external participate(1e20, 0) skipWeeks(1) advanceWeeks(1) distributeRewards {
        // it should sweep the locks
        vm.startPrank(adminAddr);
        twTap.setEmergencySweepCooldown(0);
        twTap.activateEmergencySweep();

        twTap.emergencySweep(address(tapOFT));
        twTap.emergencySweep(address(daiMock));
        twTap.emergencySweep(address(usdcMock));

        // Test lock sweep
        assertEq(tapOFT.balanceOf(adminAddr), 1e20, "twTap_emergencySweep::test_ShouldSweepTheLocks: Invalid balance");

        // Test rewards sweep

        assertEq(
            daiMock.balanceOf(adminAddr), 1e25, "twTap_emergencySweepRewards::test_ShouldSweepTheLocks: Invalid balance"
        );
        assertEq(
            usdcMock.balanceOf(adminAddr),
            1e13,
            "twTap_emergencySweepRewards::test_ShouldSweepTheLocks: Invalid balance"
        );
    }
}
