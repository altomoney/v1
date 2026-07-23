// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetFlashMinter_Test is ProtocolFeeCollectorCommon {
    address internal NEW_FLASH_MINTER = makeAddr("NewFlashMinter");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setFlashMinter(NEW_FLASH_MINTER);
    }

    function test_RevertWhen_NewFlashMinterIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setFlashMinter(address(0));
    }

    function test_RevertWhen_NewFlashMinterEqualsCurrentFlashMinter() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setFlashMinter(address(flashMinter));
    }

    function test_UpdatesFlashMinterAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.FlashMinterUpdated(address(flashMinter), NEW_FLASH_MINTER);

        vm.prank(ADMIN);
        collector.setFlashMinter(NEW_FLASH_MINTER);

        assertEq(collector.flashMinter(), NEW_FLASH_MINTER);
    }
}
