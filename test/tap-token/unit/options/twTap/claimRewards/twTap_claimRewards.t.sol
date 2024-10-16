// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {twTapBaseTest, TwTAP} from "../twTapBaseTest.sol";

contract twTap_claimRewards is twTapBaseTest {
    function test_RevertWhen_Paused() external {
        // it should revert
        vm.prank(adminAddr);
        twTap.setPause(true);

        vm.expectRevert("Pausable: paused");
        twTap.claimRewards(adminAddr, 1);
    }

    function test_ShouldReturnTheClaimableRewards()
        external
        participate(100, 0)
        skipWeeks(1)
        advanceWeeks(1)
        distributeRewards
    {
        // it should return the claimable rewards
        vm.startPrank(aliceAddr);
        twTap.claimRewards(aliceAddr, 1);
    }
}
