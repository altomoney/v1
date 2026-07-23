// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetTreasury_Test is ProtocolFeeCollectorCommon {
    address internal NEW_TREASURY = makeAddr("NewTreasury");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setTreasury(NEW_TREASURY);
    }

    function test_RevertWhen_NewTreasuryIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setTreasury(address(0));
    }

    function test_RevertWhen_NewTreasuryEqualsCurrentTreasury() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setTreasury(TREASURY);
    }

    function test_UpdatesTreasuryAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.TreasuryUpdated(TREASURY, NEW_TREASURY);

        vm.prank(ADMIN);
        collector.setTreasury(NEW_TREASURY);

        assertEq(collector.treasury(), NEW_TREASURY);
    }
}
