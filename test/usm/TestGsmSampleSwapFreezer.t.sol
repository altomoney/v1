// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestGhoBase.t.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestGsmSampleSwapFreezer is TestGhoBase {
    function testFreeze() public {
        vm.expectEmit(true, false, false, true, address(GHO_GSM));
        emit IUsm.SwapFreeze(address(GHO_GSM_SWAP_FREEZER), true);
        GHO_GSM_SWAP_FREEZER.triggerFreeze(address(GHO_GSM));
    }

    function testUnfreeze() public {
        GHO_GSM_SWAP_FREEZER.triggerFreeze(address(GHO_GSM));
        vm.expectEmit(true, false, false, true, address(GHO_GSM));
        emit IUsm.SwapFreeze(address(GHO_GSM_SWAP_FREEZER), false);
        GHO_GSM_SWAP_FREEZER.triggerUnfreeze(address(GHO_GSM));
    }

    function testRevertNotAuthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        GHO_GSM_SWAP_FREEZER.triggerFreeze(address(GHO_GSM));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        GHO_GSM_SWAP_FREEZER.triggerUnfreeze(address(GHO_GSM));
        vm.stopPrank();
    }

    function testRevertFreezeAlreadyFrozen() public {
        GHO_GSM_SWAP_FREEZER.triggerFreeze(address(GHO_GSM));

        vm.expectRevert("USM_ALREADY_FROZEN");
        GHO_GSM_SWAP_FREEZER.triggerFreeze(address(GHO_GSM));
    }

    function testRevertUnfreezeNotFrozen() public {
        vm.expectRevert("USM_ALREADY_UNFROZEN");
        GHO_GSM_SWAP_FREEZER.triggerUnfreeze(address(GHO_GSM));
    }
}
