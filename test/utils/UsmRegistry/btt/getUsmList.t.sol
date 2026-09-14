// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {UsmType} from "@alto/usm/interfaces/IUsmCommon.sol";
import {UsmRegistryCommon} from "./UsmRegistryCommon.t.sol";

contract UsmRegistry_GetUsmList_Test is UsmRegistryCommon {
    address internal immutable OWNER = makeAddr("Owner");

    UsmRegistry internal usmRegistry;
    address internal standardUsm;
    address internal advancedUsm;

    function setUp() public {
        usmRegistry = new UsmRegistry(OWNER);
        standardUsm = _deployMockUsm(UsmType.STANDARD);
        advancedUsm = _deployMockUsm(UsmType.ADVANCED_PERMISSIONS);

        vm.startPrank(OWNER);
        usmRegistry.addUsm(standardUsm);
        usmRegistry.addUsm(advancedUsm);
        vm.stopPrank();
    }

    function test_GetUsmList_ReturnsStandardUsms() public view {
        address[] memory usms = usmRegistry.getUsmList(UsmType.STANDARD);
        assertEq(usms.length, 1);
        assertEq(usms[0], standardUsm);
    }

    function test_GetUsmList_ReturnsAdvancedPermissionsUsms() public view {
        address[] memory usms = usmRegistry.getUsmList(UsmType.ADVANCED_PERMISSIONS);
        assertEq(usms.length, 1);
        assertEq(usms[0], advancedUsm);
    }

    function test_GetUsmList_ReturnsEmptyWhenNoUsmsMatchType() public {
        vm.prank(OWNER);
        usmRegistry.removeUsm(advancedUsm);

        address[] memory usms = usmRegistry.getUsmList(UsmType.ADVANCED_PERMISSIONS);
        assertEq(usms.length, 0);
    }
}
