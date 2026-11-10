// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetMinimumRewardAmount_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setMinimumRewardAmount(1 ether);
    }

    function test_RevertWhen_NewMinimumRewardAmountIsZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidMinimumRewardAmount.selector);
        collector.setMinimumRewardAmount(0);
    }

    function test_RevertWhen_NewMinimumRewardAmountEqualsCurrentValue() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setMinimumRewardAmount(INITIAL_MINIMUM_REWARD_AMOUNT);
    }

    function test_OwnerUpdatesMinimumRewardAmountAndEmits() public {
        uint256 newMinimumRewardAmount = 250 ether;

        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.MinimumRewardAmountUpdated(
            INITIAL_MINIMUM_REWARD_AMOUNT, newMinimumRewardAmount
        );
        vm.prank(ADMIN);
        collector.setMinimumRewardAmount(newMinimumRewardAmount);

        assertEq(collector.minimumRewardAmount(), newMinimumRewardAmount);
    }
}
