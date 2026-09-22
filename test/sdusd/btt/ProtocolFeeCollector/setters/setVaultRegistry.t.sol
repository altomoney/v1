// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetVaultRegistry_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setVaultRegistry(address(1));
    }

    function test_RevertWhen_NewVaultRegistryIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setVaultRegistry(address(0));
    }

    function test_RevertWhen_NewVaultRegistryEqualsCurrentRegistry() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setVaultRegistry(address(vaultRegistry));
    }

    function test_UpdatesVaultRegistryAndEmitsEvent() public {
        VaultRegistry newRegistry = new VaultRegistry(ADMIN);

        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.VaultRegistryUpdated(address(vaultRegistry), address(newRegistry));

        vm.prank(ADMIN);
        collector.setVaultRegistry(address(newRegistry));

        assertEq(address(collector.vaultRegistry()), address(newRegistry));
    }
}
