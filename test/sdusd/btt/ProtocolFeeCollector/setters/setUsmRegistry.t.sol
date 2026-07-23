// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetUsmRegistry_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setUsmRegistry(address(1));
    }

    function test_RevertWhen_NewUsmRegistryIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setUsmRegistry(address(0));
    }

    function test_RevertWhen_NewUsmRegistryEqualsCurrentRegistry() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setUsmRegistry(address(usmRegistry));
    }

    function test_UpdatesUsmRegistryAndEmitsEvent() public {
        UsmRegistry newRegistry = new UsmRegistry(ADMIN);

        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.UsmRegistryUpdated(address(usmRegistry), address(newRegistry));

        vm.prank(ADMIN);
        collector.setUsmRegistry(address(newRegistry));

        assertEq(address(collector.usmRegistry()), address(newRegistry));
    }
}
