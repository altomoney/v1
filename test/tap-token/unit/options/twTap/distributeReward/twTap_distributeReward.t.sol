// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {twTapBaseTest, TwTAP} from "../twTapBaseTest.sol";
import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";

contract twTap_distributeReward is twTapBaseTest {
    function test_RevertWhen_AmountIsZero() external skipWeeks(1) advanceWeeks(1) {
        // it should revert
        vm.expectRevert(ITWTAPv2.NotValid.selector);
        twTap.distributeReward(1, 0);
    }

    function test_RevertWhen_RewardTokenIsZero() external skipWeeks(1) advanceWeeks(1) {
        // it should revert
        vm.expectRevert(ITWTAPv2.NotValid.selector);
        twTap.distributeReward(0, 1e18);
    }

    function test_ShouldDistributeTheReward()
        external
        addRewardTokens
        participate(100, 0)
        skipWeeks(1)
        advanceWeeks(1)
    {
        // it should distribute the reward
        vm.startPrank(adminAddr);
        daiMock.mintTo(adminAddr, 1e18);
        daiMock.approve(address(twTap), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit ITWTAPv2.DistributeReward(address(daiMock), adminAddr, 1e18, 1);
        twTap.distributeReward(1, 1e18);

        assertEq(
            daiMock.balanceOf(address(twTap)),
            1e18,
            "twTap_distributeReward::test_ShouldDistributeTheReward: Invalid balance"
        );
    }
}
