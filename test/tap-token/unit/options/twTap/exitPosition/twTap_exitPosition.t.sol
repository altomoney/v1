// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {twTapBaseTest, TwTAP} from "../twTapBaseTest.sol";
import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";

contract twTap_exitPosition is twTapBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    modifier advanceTime(uint256 _time) {
        vm.warp(block.timestamp + _time);
        _;
    }

    function test_exitPosition_valid()
        external
        participate(100, 0)
        advanceTime(EPOCH_DURATION * 2)
        advanceWeeks(2)
        distributeRewards
    {
        vm.startPrank(aliceAddr);
        twTap.claimRewards(aliceAddr, 0);
        twTap.exitPosition(aliceAddr, aliceAddr, 0);
        vm.stopPrank();
    }

    function test_exitPosition_invalid_notAuthorized(address _participant)
        external
        participate(100, 0)
        advanceTime(EPOCH_DURATION * 2)
        advanceWeeks(2)
        distributeRewards
    {
        vm.assume(_participant != aliceAddr);

        vm.startPrank(aliceAddr);
        twTap.claimRewards(aliceAddr, 0);
        vm.stopPrank();


        vm.startPrank(_participant);
        vm.expectRevert(ITWTAPv2.NotAuthorized.selector);
        twTap.exitPosition(aliceAddr, aliceAddr, 0);
        vm.stopPrank();
    }
}
