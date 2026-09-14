// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UsmRegistryCommon} from "./UsmRegistryCommon.t.sol";

contract UsmRegistry_Constructor_Test is UsmRegistryCommon {
    address internal immutable OWNER = makeAddr("Owner");

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new UsmRegistry(address(0));
    }

    function test_Constructor_SetsOwnerAndInitialState() public {
        UsmRegistry usmRegistry = new UsmRegistry(OWNER);
        assertEq(usmRegistry.owner(), OWNER);
        assertEq(usmRegistry.getUsmListLength(), 0);

        address[] memory list = usmRegistry.getUsmList();
        assertEq(list.length, 0);
    }
}
