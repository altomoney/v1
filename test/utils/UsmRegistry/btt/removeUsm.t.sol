// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UsmRegistryCommon} from "./UsmRegistryCommon.t.sol";

contract UsmRegistry_RemoveUsm_Test is UsmRegistryCommon {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");

    UsmRegistry internal usmRegistry;

    event UsmRemoved(address indexed usm);

    function setUp() public {
        usmRegistry = new UsmRegistry(OWNER);
        address usm = makeAddr("RegisteredUsm");
        vm.prank(OWNER);
        usmRegistry.addUsm(usm);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        address usm = usmRegistry.getUsmAtIndex(0);
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        usmRegistry.removeUsm(usm);
    }

    function test_RevertWhen_UsmIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IUsmRegistry.UsmRegistryZeroAddress.selector);
        usmRegistry.removeUsm(address(0));
    }

    function test_RevertWhen_UsmIsNotRegistered() public {
        vm.prank(OWNER);
        vm.expectRevert(IUsmRegistry.UsmRegistryUsmDoesNotExist.selector);
        usmRegistry.removeUsm(makeAddr("NotRegistered"));
    }

    function test_RemoveUsm_WhenUsmIsRegistered() public {
        address usm = usmRegistry.getUsmAtIndex(0);
        assertTrue(usmRegistry.isUsm(usm));

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit UsmRemoved(usm);
        usmRegistry.removeUsm(usm);

        assertFalse(usmRegistry.isUsm(usm));
        assertEq(usmRegistry.getUsmListLength(), 0);
    }
}
