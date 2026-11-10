// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetSdusdVault_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setSdusdVault(address(sdusdVault));
    }

    function test_RevertWhen_NewSdusdVaultIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setSdusdVault(address(0));
    }

    function test_RevertWhen_NewSdusdVaultEqualsCurrentVault() public {
        _setSdusdVault();

        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setSdusdVault(address(sdusdVault));
    }

    function test_UpdatesSdusdVaultAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.SdusdUpdated(address(0), address(sdusdVault));

        _setSdusdVault();

        assertEq(collector.sdusdVault(), address(sdusdVault));
    }
}
