// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestUsmSampleSwapFreezer is TestDusdBase {
    function testFreeze() public {
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.SwapFreeze(address(DUSD_USM_SWAP_FREEZER), true);
        DUSD_USM_SWAP_FREEZER.triggerFreeze(address(DUSD_USM));
    }

    function testUnfreeze() public {
        DUSD_USM_SWAP_FREEZER.triggerFreeze(address(DUSD_USM));
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.SwapFreeze(address(DUSD_USM_SWAP_FREEZER), false);
        DUSD_USM_SWAP_FREEZER.triggerUnfreeze(address(DUSD_USM));
    }

    function testRevertNotAuthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        DUSD_USM_SWAP_FREEZER.triggerFreeze(address(DUSD_USM));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        DUSD_USM_SWAP_FREEZER.triggerUnfreeze(address(DUSD_USM));
        vm.stopPrank();
    }

    function testRevertFreezeAlreadyFrozen() public {
        DUSD_USM_SWAP_FREEZER.triggerFreeze(address(DUSD_USM));

        vm.expectRevert("USM_ALREADY_FROZEN");
        DUSD_USM_SWAP_FREEZER.triggerFreeze(address(DUSD_USM));
    }

    function testRevertUnfreezeNotFrozen() public {
        vm.expectRevert("USM_ALREADY_UNFROZEN");
        DUSD_USM_SWAP_FREEZER.triggerUnfreeze(address(DUSD_USM));
    }
}
