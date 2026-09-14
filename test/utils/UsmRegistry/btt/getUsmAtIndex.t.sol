// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {UsmRegistryCommon} from "./UsmRegistryCommon.t.sol";

contract UsmRegistry_GetUsmAtIndex_Test is UsmRegistryCommon {
    address internal immutable OWNER = makeAddr("Owner");

    UsmRegistry internal usmRegistry;

    address internal usmA;
    address internal usmB;
    address internal usmC;

    function setUp() public {
        usmRegistry = new UsmRegistry(OWNER);
        usmA = makeAddr("UsmA");
        usmB = makeAddr("UsmB");
        usmC = makeAddr("UsmC");

        vm.startPrank(OWNER);
        usmRegistry.addUsm(usmA);
        usmRegistry.addUsm(usmB);
        usmRegistry.addUsm(usmC);
        vm.stopPrank();
    }

    function test_RevertWhen_IndexIsEqualToLength() public {
        vm.expectRevert(IUsmRegistry.UsmRegistryInvalidIndex.selector);
        usmRegistry.getUsmAtIndex(3);
    }

    function test_RevertWhen_IndexIsGreaterThanLength() public {
        vm.expectRevert(IUsmRegistry.UsmRegistryInvalidIndex.selector);
        usmRegistry.getUsmAtIndex(100);
    }

    function test_RevertWhen_ListIsEmpty() public {
        UsmRegistry emptyRegistry = new UsmRegistry(OWNER);
        vm.expectRevert(IUsmRegistry.UsmRegistryInvalidIndex.selector);
        emptyRegistry.getUsmAtIndex(0);
    }

    function test_GetUsmAtIndex_WhenIndexIsValid() public view {
        assertEq(usmRegistry.getUsmAtIndex(0), usmA);
        assertEq(usmRegistry.getUsmAtIndex(1), usmB);
        assertEq(usmRegistry.getUsmAtIndex(2), usmC);
    }
}
