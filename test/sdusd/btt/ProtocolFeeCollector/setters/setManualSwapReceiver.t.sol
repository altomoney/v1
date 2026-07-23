// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetManualSwapReceiver_Test is ProtocolFeeCollectorCommon {
    address internal NEW_RECEIVER = makeAddr("NewManualSwapReceiver");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setManualSwapReceiver(NEW_RECEIVER);
    }

    function test_RevertWhen_NewReceiverIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setManualSwapReceiver(address(0));
    }

    function test_RevertWhen_NewReceiverEqualsCurrentReceiver() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setManualSwapReceiver(MANUAL_SWAP_RECEIVER);
    }

    function test_UpdatesManualSwapReceiverAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.ManualSwapReceiverUpdated(MANUAL_SWAP_RECEIVER, NEW_RECEIVER);

        vm.prank(ADMIN);
        collector.setManualSwapReceiver(NEW_RECEIVER);

        assertEq(collector.manualSwapReceiver(), NEW_RECEIVER);
    }
}
