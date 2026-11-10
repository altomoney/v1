// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetRewardsBps_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setRewardsBps(1);
    }

    function test_RevertWhen_NewRewardsBpsExceedsPercentagePrecision() public {
        uint256 invalidRewardsBps = collector.PERCENTAGE_PRECISION() + 1;

        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidRewardsBps.selector);
        collector.setRewardsBps(invalidRewardsBps);
    }

    function test_RevertWhen_NewRewardsBpsEqualsCurrentValue() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setRewardsBps(INITIAL_REWARDS_BPS);
    }

    function test_AllowsZeroAndEmitsEvent() public {
        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.RewardsBpsUpdated(INITIAL_REWARDS_BPS, 0);

        _setRewardsBps(0);

        assertEq(collector.rewardsBps(), 0);
    }

    function test_AllowsPercentagePrecisionAndEmitsEvent() public {
        uint256 newRewardsBps = collector.PERCENTAGE_PRECISION();
        vm.expectEmit(false, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.RewardsBpsUpdated(INITIAL_REWARDS_BPS, newRewardsBps);

        _setRewardsBps(newRewardsBps);

        assertEq(collector.rewardsBps(), newRewardsBps);
    }
}
