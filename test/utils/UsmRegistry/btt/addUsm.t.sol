// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UsmRegistryCommon} from "./UsmRegistryCommon.t.sol";

contract UsmRegistry_AddUsm_Test is UsmRegistryCommon {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");

    UsmRegistry internal usmRegistry;

    event UsmAdded(address indexed usm);

    function setUp() public {
        usmRegistry = new UsmRegistry(OWNER);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        usmRegistry.addUsm(makeAddr("Usm"));
    }

    function test_RevertWhen_UsmIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IUsmRegistry.UsmRegistryZeroAddress.selector);
        usmRegistry.addUsm(address(0));
    }

    function test_RevertWhen_UsmAlreadyRegistered() public {
        address usm = makeAddr("Usm");
        vm.prank(OWNER);
        usmRegistry.addUsm(usm);

        vm.prank(OWNER);
        vm.expectRevert(IUsmRegistry.UsmRegistryUsmAlreadyExists.selector);
        usmRegistry.addUsm(usm);
    }

    function test_AddUsm_WhenUsmIsNotRegistered() public {
        address usm = makeAddr("Usm");
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit UsmAdded(usm);
        usmRegistry.addUsm(usm);

        assertTrue(usmRegistry.isUsm(usm));
        assertEq(usmRegistry.getUsmListLength(), 1);
        assertEq(usmRegistry.getUsmList()[0], usm);
        assertEq(usmRegistry.getUsmAtIndex(0), usm);
    }
}
