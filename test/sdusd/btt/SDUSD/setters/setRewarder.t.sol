// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ISDUSDVaultErrors, ISDUSDVaultEvents} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {SDUSDCommon} from "../SDUSDCommon.t.sol";

contract SDUSD_SetRewarder_Test is SDUSDCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        vault.setRewarder(NEW_REWARDER);
    }

    function test_RevertWhen_NewRewarderIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDZeroAddress.selector);
        vault.setRewarder(address(0));
    }

    function test_RevertWhen_NewRewarderEqualsCurrentRewarder() public {
        vm.prank(ADMIN);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNoStateChange.selector);
        vault.setRewarder(address(collector));
    }

    function test_UpdatesRewarderAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit ISDUSDVaultEvents.RewarderUpdated(address(collector), NEW_REWARDER);
        vm.prank(ADMIN);
        vault.setRewarder(NEW_REWARDER);

        assertEq(vault.rewarder(), NEW_REWARDER);
    }
}
