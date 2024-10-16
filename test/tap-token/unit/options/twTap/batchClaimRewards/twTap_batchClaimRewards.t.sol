// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {twTapBaseTest, TwTAP} from "../twTapBaseTest.sol";

contract twTap_batchClaimRewards is twTapBaseTest {
    function test_RevertWhen_Paused() external participate(100, 0) skipWeeks(1) advanceWeeks(1) distributeRewards {
        // it should revert
        vm.prank(adminAddr);
        twTap.setPause(true);

        vm.expectRevert("Pausable: paused");
        uint256[] memory bucketIds = new uint256[](2);
        bucketIds[0] = 1;
        bucketIds[1] = 2;
        vm.prank(adminAddr);
        twTap.batchClaimRewards(adminAddr, bucketIds);
    }

    function test_ShouldReturnTheClaimableRewards()
        external
        participate(100, 0)
        participate(100, 0)
        skipWeeks(1)
        advanceWeeks(1)
        distributeRewards
    {
        // it should return the claimable rewards
        vm.startPrank(aliceAddr);
        uint256[] memory bucketIds = new uint256[](2);
        bucketIds[0] = 1;
        bucketIds[1] = 2;
        vm.prank(aliceAddr);
        twTap.batchClaimRewards(aliceAddr, bucketIds);
    }
}
